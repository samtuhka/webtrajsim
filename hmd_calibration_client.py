'''
HMD calibration client example.
This script shows how to talk to Pupil Capture or Pupil Service
and run a gaze mapper calibration.
'''
import zmq, msgpack, time
import websocket
import thread
import time
from SimpleWebSocketServer import SimpleWebSocketServer, WebSocket
from threading import Thread
import json
import sys

clients = []
webtrajsim = 0

class Socket(WebSocket):

    def handleMessage(self):
        if self.data == "calibration" or self.data == "verification":
            global webtrajsim
            webtrajsim = self
        for client in clients:
            if client != self:
                client.sendMessage(self.data)

    def handleConnected(self):
       print(self.address, 'connected')
       clients.append(self)

    def handleClose(self):
       clients.remove(self)
       print(self.address, 'closed')
       if self == webtrajsim:
           for client in clients:
                client.sendMessage('stop')

server = SimpleWebSocketServer('', 10103, Socket)

thread = Thread(target = server.serveforever)
thread.start()
time.sleep(1)

ctx = zmq.Context()

ws = websocket.WebSocket()
ws = websocket.create_connection("ws://localhost:10103")

#create a zmq REQ socket to talk to Pupil Service/Capture
req = ctx.socket(zmq.REQ)
req.connect('tcp://192.168.56.1:50020')

#convenience functions
def send_recv_notification(n):
    # REQ REP requirese lock step communication with multipart msg (topic,msgpack_encoded dict)
    req.send_multipart(('notify.%s'%n['subject'], msgpack.dumps(n)))
    return req.recv()

def get_pupil_timestamp():
    req.send('t') #see Pupil Remote Plugin for details
    return float(req.recv())

n = {'subject': 'recording.should_stop'}
print send_recv_notification(n)
time.sleep(2)

n = {'subject': 'recording.should_start', 'session_name': sys.argv[1]}
print send_recv_notification(n)
time.sleep(2)

# set start eye windows
n = {'subject':'eye_process.should_start.0','eye_id':0, 'args':{}}
print send_recv_notification(n)
n = {'subject':'eye_process.should_start.1','eye_id':1, 'args':{}}
print send_recv_notification(n)
time.sleep(2)

def cleaner(data, timestamps):
    data = np.array(data)
    changeLocs = (np.diff(data[:,0]) != 0) | (np.diff(data[:,1]) != 0)
    data = data[1:]
    timestamps = np.array(timestamps)[1:]
    valid = np.ones(len(timestamps), dtype=bool)
    for loc in data[changeLocs]:
        index = np.where(data == loc)[0][0]
        ts = timestamps[index]
        removed = (timestamps >= ts) & (timestamps <= ts + 0.5)
        valid = valid & ~removed
    ref_data = []
    
    for pos, t in zip(data[valid], timestamps[valid]):
        datum0 = {'norm_pos':pos,'timestamp':t,'id':0}
        datum1 = {'norm_pos':pos,'timestamp':t,'id':1}
        ref_data.append(datum0)
        ref_data.append(datum1)
    return ref_data

while True:
    res = ws.recv()
    
    if res != "calibration":
        continue
    
    # set calibration method to hmd calibration
    n = {'subject':'start_plugin','name':'HMD_Calibration', 'args':{}}
    print send_recv_notification(n)

    # start caliration routine with params. This will make pupil start sampeling pupil data.
    n = {'subject':'calibration.should_start', 'hmd_video_frame_size':(1000,1000), 'outlier_threshold':35}
    print send_recv_notification(n)
    
    positions = []
    timestamps = []
    
    while True:
        message = "getCalib"
        ws.send(message)
        result = ws.recv()
        print result
        t = get_pupil_timestamp()
        if result != "start" and result != "stop":
                result = json.loads(result)
                pos = (result['position']['x']/10.0, result['position']['y']/10.0) #, result['position']['z'])
                positions.append(pos)
                timestamps.append(t)
        if result == "stop":
            ref_data = cleaner(positions, timestamps)
            break
        
    print "finished"

    # Send ref data to Pupil Capture/Service:
    # This notification can be sent once at the end or multiple times.
    # During one calibraiton all new data will be appended.
    n = {'subject':'calibration.add_ref_data','ref_data':ref_data}
    print send_recv_notification(n)

    # stop calibration
    # Pupil will correlate pupil and ref data based on timestamps,
    # compute the gaze mapping params, and start a new gaze mapper.
    n = {'subject':'calibration.should_stop'}
    print send_recv_notification(n)

    time.sleep(2)
    n = {'subject':'service_process.should_stop'}
    print send_recv_notification(n)



