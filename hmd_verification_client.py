import zmq, msgpack, time
import websocket
import time
import json
import sys
from msgpack import loads
time.sleep(2)

ctx = zmq.Context()
addr = '127.0.0.1' 
ws = websocket.WebSocket()
ws = websocket.create_connection("ws://localhost:10103")

#create a zmq REQ socket to talk to Pupil Service/Capture
req = ctx.socket(zmq.REQ)
req.connect('tcp://192.168.56.1:50020')

req.send_string('SUB_PORT')
sub_port = req.recv_string()

# open a sub port to listen to pupil
sub = ctx.socket(zmq.SUB)
sub.connect("tcp://192.168.56.1:{}".format(sub_port))
sub.setsockopt_string(zmq.SUBSCRIBE, 'gaze')

while True:
    res = ws.recv()
    
    if res != "verification":
        continue
        
    while True:
        topic = sub.recv_string()
        msg = sub.recv()  # bytes
        gaze = loads(msg, encoding='utf-8')
        pos = gaze['norm_pos']
        pos = {'x': pos[0], 'y': pos[1]}
        ws.send(json.dumps(pos))
        result = ws.recv()
        if result == "stop":
            break
        
    print("finished verification")
