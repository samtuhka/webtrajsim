import zmq, msgpack, time
import websocket
import time
import json
import sys
from msgpack import loads
import pickle
import os

def save_object(object,file_path):
	file_path = os.path.expanduser(file_path)
	with open(file_path,'wb') as fh:
		pickle.dump(object,fh,-1)
		
time.sleep(2)

ctx = zmq.Context()
addr = '127.0.0.1' 
ws = websocket.WebSocket()
ws = websocket.create_connection("ws://localhost:10103")

#create a zmq REQ socket to talk to Pupil Service/Capture
req = ctx.socket(zmq.REQ)

req.connect('tcp://0.0.0.0:{}'.format(sys.argv[2]))

req.send_string('SUB_PORT')
sub_port = req.recv_string()

# open a sub port to listen to pupil
sub = ctx.socket(zmq.SUB)
sub.connect("tcp://192.168.56.1:{}".format(sub_port))
sub.setsockopt_string(zmq.SUBSCRIBE, 'gaze')

while True:
    res = ws.recv()
    
    if res != "start verification":
        continue
    
    verifData = []
    
    while True:
        topic = sub.recv_string()
        msg = sub.recv()  # bytes
        gaze = loads(msg, encoding='utf-8')
        pos = gaze['norm_pos']
        #pos = gaze['gaze_point_3d']
        #normal = gaze['gaze_normals_3d']
        #if 1 in normal.keys():
        #   normal = normal[1]
        #else:
        #   normal = normal[0]
        pos = {'x': pos[0], 'y': pos[1], 'conf': gaze['confidence'], 'id': gaze['id'], 'time': gaze['timestamp']} #, 'z': pos[2], 'xn': normal[0], 'yn': normal[1], 'zn': normal[2]}
        ws.send(json.dumps(pos))
        result = ws.recv()
        if result == "stop":
            break
        else:
            result = json.loads(result)
            result['gaze'] = gaze
            verifData.append(result)
        
    save_object(verifData, sys.argv[1] + str(time.time()))            
        
    print("finished verification")
