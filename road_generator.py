import matplotlib.pyplot as plt
import numpy as np
from scipy.special import fresnel
import json
import math


dist = 0



def curve(start, end, xad = 0, yad = 0, order = 1):
    arc = np.linspace(start, end, 1200)
    x = np.cos(arc) + xad
    y = np.sin(arc) + yad
    return x[::order], y

def rotate(rad,x,y):
    x1 = math.cos(rad)*x - math.sin(rad)*y
    y1 = math.sin(rad)*x + math.cos(rad)*y
    return x1, y1


dur = 1
yaw_dur = dur*1
yaw_rate = 40


tracks = []
for track in range(10):
    x_list = []
    y_list = []

    x_adj = 0
    y_adj = 0
    for i in range(0,20):
        s = (2*np.pi)/(360/yaw_rate)*dur

        c = (yaw_rate/360*yaw_dur)*np.pi
        x,y = curve(np.pi, np.pi + c, 0)
        #plt.plot(x,y)

        x2,y2 = curve(c,0, -2*np.cos(c),  -2*np.sin(c))
        #plt.plot(x2,y2)
        #plt.show()
        rand = np.random.randint(0,1)
        r = rand*s

        x3,y3 = rotate(-c, x2, y2)
        x3 += x2[-1] + 1
        y3 += -2*np.sin(c) -r
        
        x4,y4 = rotate(-c,x,y)
        y4 += -np.sin(c)*4 -r

        addx = np.array(x.tolist() + x2.tolist() + x3.tolist() + x4.tolist())
        addy = np.array(y.tolist() + y2.tolist() + y3.tolist() + y4.tolist())
        
        left_chance = np.random.random()    

        if left_chance > 0.5:
            addx, addy = rotate(np.pi, addx, addy)
            addx -= 2
            addy = addy[::-1]
            addy += y_adj + (y4[-1] - y[0])
        else:
            addy += y_adj
        rand = np.random.randint(4,7)
        
        y_adj += (y4[-1] - y[0]) - rand*s

        x_list += addx.tolist()
        y_list += addy.tolist()

    x_list = [-1] + x_list + [-1]
    y_list = [10*s] + y_list + [y_list[-1] - 10*s]
    tracks.append([x_list, y_list])
    with open('./res/tracks/track_{}_x.json'.format(track), 'w') as outfile:
        json.dump(x_list, outfile)
    with open('./res/tracks/track_{}_y.json'.format(track), 'w') as outfile:
        json.dump(y_list, outfile)
with open('./res/tracks/all_tracks.json'.format(track), 'w') as outfile:
    json.dump(tracks, outfile)
plt.plot(np.array(y_list),np.array(x_list),  color = 'red')
#plt.axes().set_aspect('equal')
plt.show()