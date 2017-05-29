import zmq, msgpack, time
import websocket
import time
from SimpleWebSocketServer import SimpleWebSocketServer, WebSocket
from threading import Thread
import json
import sys
import numpy as np
import pickle
import os
from uvc import get_time_monotonic

def save_object(object,file_path):
	file_path = os.path.expanduser(file_path)
	with open(file_path,'wb') as fh:
		pickle.dump(object,fh,-1)

		
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
	datum0 = {'norm_pos': (pos[0]  + 0.5, pos[1]  + 0.5),'timestamp':t,'id':0, 'mm_pos': (pos[0] * 1000, pos[1] * 1000, -pos[2] * 1000)}
	datum1 = {'norm_pos': (pos[0]  + 0.5, pos[1]  + 0.5),'timestamp':t,'id':1, 'mm_pos': (pos[0] * 1000, pos[1] * 1000, -pos[2] * 1000)}
	ref_data.append(datum0)
	ref_data.append(datum1)
    return ref_data

class Socket(WebSocket):

    def handleMessage(self):
	if self.data == "Webtrajsim here":
	    global webtrajsim
	    webtrajsim = self.address
	else:
		for client in clients:
			if client != self:
				client.sendMessage(self.data)

    def handleConnected(self):
       print(self.address, 'connected')
       clients.append(self)

    def handleClose(self):
       clients.remove(self)
       print(self.address, 'closed')
       if self.address == webtrajsim:
	   for client in clients:
		client.sendMessage('stop')
		
if __name__ == '__main__':
    
    clients = []
    webtrajsim = 0
    
    server = SimpleWebSocketServer('', 10103, Socket)

    thread = Thread(target = server.serveforever)
    thread.start()
    time.sleep(1)

    ctx = zmq.Context()

    ws = websocket.WebSocket()
    ws = websocket.create_connection("ws://localhost:10103")

    #create a zmq REQ socket to talk to Pupil Service/Capture
    req = ctx.socket(zmq.REQ)

    req.connect('tcp://0.0.0.0:{}'.format(sys.argv[3]))

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
    time.sleep(10)

    # set start eye windows
    n = {'subject':'eye_process.should_start.0','eye_id':0, 'args':{}}
    print send_recv_notification(n)
    n = {'subject':'eye_process.should_start.1','eye_id':1, 'args':{}}
    print send_recv_notification(n)
    time.sleep(2)

    # set current Pupil time to 0.0
    t = time.time()
    req.send_string('T 0.0')
    print(req.recv_string())
    delay = time.time()-t
    print('Round trip command delay:', delay)
    with open(sys.argv[2] + "/pupil_info.txt", "w") as text_file:
      text_file.write("Pupil timebase: %f" % (0.0))
      text_file.write("\nTimebase set at: %f" % (t))
      text_file.write("\nRoundtrip delay: %f" % (delay))


    n = {'subject': 'recording.should_start', 'session_name': sys.argv[1]}
    print send_recv_notification(n)
    time.sleep(2)

    # set calibration method to hmd calibration
    n = {'subject':'start_plugin','name':'HMD_Calibration', 'args':{}}
    print send_recv_notification(n)

    while True:
	res = ws.recv()
	
	if res != "start calibration":
	    continue
	
	# start caliration routine with params. This will make pupil start sampeling pupil data.
	n = {'subject':'calibration.should_start', 'hmd_video_frame_size':(1080,1200), 'outlier_threshold':35}
	print send_recv_notification(n)
	
	positions = []
	timestamps = []
	ref_data = []
	calibData = []
	
	while True:
	    message = "getCalib"
	    ws.send(message)
	    result = ws.recv()
	    t = get_pupil_timestamp()
	    
	    if result == "stop":
		if len(positions) > 0:
		    ref_data = cleaner(positions, timestamps)
		break
	    else:
		    result = json.loads(result)
		    pos = (result['position']['x'], result['position']['y'], result['position']['z'])
		    positions.append(pos)
		    result['pupil_timestamp'] = t
		    calibData.append(result)
		    timestamps.append(t)

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
	#n = {'subject':'service_process.should_stop'}
	#print send_recv_notification(n)

	save_object(calibData, sys.argv[2] + str(time.time()))



