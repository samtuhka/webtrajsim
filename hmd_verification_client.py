import zmq, msgpack, time
import websocket
import time
import json
import sys
from msgpack import loads
import pickle
import os
import matplotlib.pyplot as plt
import numpy as np
import scipy.spatial as sp

import pyqtgraph as pg
import pyqtgraph.exporters
import _thread
from pyqtgraph.Qt import QtGui, QtCore, USE_PYSIDE, USE_PYQT5

class plotter():
  def __init__(self):
    self.gaze = [-1,-1]
    self.ref = [-1,-1]
    self.updateGaze = False
    self.text = ""
    self.clear = False
    self.verif = 1
    self.finished = False
    _thread.start_new_thread(self.thread, ())

  def update(self):
    line = np.array([self.gaze, self.ref])
    self.plt.plot(x = np.array([self.ref[0]]), y = np.array([self.ref[1]]), pen=None, symbol='o', symbolPen = 'b')
    if self.updateGaze:
     self.plt.plot(line, pen='w', symbol=None)
     self.plt.plot(x = np.array([self.gaze[0]]), y = np.array([self.gaze[1]]), pen=None, symbol='o', symbolPen = 'r')
     self.updateGaze = False
    if self.text:
     txt = pg.TextItem(self.text)
     txt.setPos(0.5, 0.5)
     self.plt.addItem(txt)
     self.text = ""
    if self.clear and self.finished:
     self.plt_init()
     self.verif += 1
     self.finished = False
     self.clear = False

  
  def plt_init(self):
   self.plt = pg.plot(title="Verification " + str(self.verif))
   self.plt.setXRange(-0.75, 0.75, padding=0)
   self.plt.setYRange(-0.75, 0.75, padding=0)
   self.gaze = [-1,-1]
   self.ref = [-1,-1]
   
  def thread(self):
   self.plt_init()
   timer = QtCore.QTimer()
   timer.timeout.connect(self.update)
   timer.start(0)
   pg.QtGui.QApplication.exec_()




def calc_result(pt_cloud):
    pt_cloud[:,2:4] = pt_cloud[:,2:4] + 0.5
    res = 1
    field_of_view = 20
    px_per_degree = res/field_of_view

    gaze,ref = pt_cloud[:,0:2],pt_cloud[:,2:4]
    error_lines = np.array([[g,r] for g,r in zip(gaze,ref)])
    error_lines = error_lines.reshape(-1,2)
    error_mag = sp.distance.cdist(gaze,ref).diagonal().copy()
    
    accuracy_pix = np.mean(error_mag)
    #print("Gaze error mean in world camera pixel: %f"%accuracy_pix)
    error_mag /= px_per_degree
    #print('Error in degrees: %s'%error_mag)
    #print('Outliers: %s'%np.where(error_mag>=5.))
    accuracy = np.mean(error_mag[error_mag<5.])


    gaze_h = gaze[:,0]
    ref_h = ref[:,0]
    error_h = np.abs(gaze_h - ref_h)
    error_h /= px_per_degree
    accuracy_h = np.mean(error_h[error_mag<5.])

    gaze_v = gaze[:,1]
    ref_v = ref[:,1]
    error_v = np.abs(gaze_v - ref_v)
    error_v /= px_per_degree
    accuracy_v = np.mean(error_v[error_mag<5.])
    print('Angular accuracy: %s (hor: %s, ver: %s)' %(accuracy, accuracy_h, accuracy_v))


    error_h_alt = (gaze_h - ref_h)
    error_h_alt /= px_per_degree
    accuracy_h_alt = np.mean(error_h_alt[error_mag<5.])

    error_v_alt = (gaze_v - ref_v)
    error_v_alt /= px_per_degree
    accuracy_v_alt = np.mean(error_v_alt[error_mag<5.])


    return accuracy

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
sub.connect("tcp://0.0.0.0:{}".format(sub_port))
sub.setsockopt_string(zmq.SUBSCRIBE, 'gaze')
plotter = plotter()

while True:
    plotter.clear = True
    res = ws.recv()
  
    if res != "start verification":
        continue
    
    verifData = []
    refPoints = []
    prevT = 0

    #plt.figure("verification", figsize=(10, 10))
    #plt.clf()
    #plt.axes().set_aspect('equal')
    #plt.xlim(-0.75, 0.75)
    #plt.ylim(-0.75, 0.75)
    #plt.ion()
    
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
        eye_id = 3
        if 'id' in gaze:
          eye_id = gaze['id']
        pos = {'x': pos[0], 'y': pos[1], 'conf': gaze['confidence'], 'id': eye_id, 'time': gaze['timestamp']} #, 'z': pos[2], 'xn': normal[0], 'yn': normal[1], 'zn': normal[2]}
        ws.send(json.dumps(pos))
        result = ws.recv()
        if result == "stop":
            print(pos['time'] - prevT)
            break
        else:
            prevT = pos['time']
            result = json.loads(result)
            result['gaze'] = gaze
            result['received_timestamp'] = time.time()
            refPoints.append([pos['x'], pos['y'], result['position']['x'], result['position']['y'], gaze['confidence'], gaze['timestamp']])
            plotter.ref = [result['position']['x'], result['position']['y']]
            verifData.append(result)
            if gaze['confidence'] > 0.5:
              plotter.gaze = [pos['x'] - 0.5, pos['y'] - 0.5]
              plotter.updateGaze = True
            #  plt.plot(result['position']['x'], result['position']['y'], 'o', color = 'blue', label = 'markers')
            #  plt.plot(pos['x'] - 0.5, pos['y'] - 0.5, '.', color = 'red', label = 'gaze', alpha = 0.5)
            #  plt.plot([pos['x'] - 0.5, result['position']['x']], [pos['y'] - 0.5, result['position']['y']], color = 'yellow', linewidth=0.1, alpha = 0.95)
            #  plt.show()
            #  plt.pause(0.000001)
        
    save_object(verifData, sys.argv[1] + str(time.time()))
    refPoints = np.array(refPoints)
    np.save("{}verification_{}.npy".format(sys.argv[1], plotter.verif), refPoints)
    size = len(refPoints)
    refPoints = refPoints[refPoints[:,4] > 0.5]
    sizeCleaned = len(refPoints)
    print("valid: " + str(sizeCleaned/size))
    plotter.finished = True
    gaze, ref = refPoints[:,0:2],refPoints[:,2:4]


    result = calc_result(refPoints)
    plotter.text = str(result)
    #plt.text(0.5, 0.5, "Accuracy: " + str(result))
    #plt.pause(0.000001)

    print("finished verification")
