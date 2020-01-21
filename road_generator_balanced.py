import matplotlib.pyplot as plt
import numpy as np
from scipy.special import fresnel
import json
import math
import random

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

while True:
    dur = 1
    yaw_dur = dur*1
    yaw_rate = 40

    turn_n = 20


    tracks = []

    for track in range(3):
        x_list = []
        y_list = []
        #print(straights)
        #straights = random.sample(straights, len(straights))
        while True:
            straights = [np.random.randint(5,8) for i in range(turn_n - 1)]
            if np.sum(straights) == 6*len(straights):
                break

        left = [0]*10 + 10*[1]
        left = random.sample(left, 20)
        x_adj = 0
        y_adj = 0
        for i in range(0,turn_n):
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
            if i < turn_n - 1:
                y_adj += (y4[-1] - y[0]) - straights[i]*s
            else:
                y_adj += (y4[-1] - y[0])

            x_list += addx.tolist()
            y_list += addy.tolist()

        #x_list = [-1] + x_list + [-1]
        #y_list = [10*s] + y_list + [y_list[-1] - 100*s]
        tracks.append([x_list, y_list])

    left_turns = 0
    for track in range(10):
        x_list = []
        y_list = []
        #print(straights)
        #straights = random.sample(straights, len(straights))
        while True:
            straights = [np.random.randint(5,8) for i in range(turn_n - 1)]
            if np.sum(straights) == 6*len(straights):
                break

        left = [0]*10 + 10*[1]
        left = random.sample(left, 20)
        x_adj = 0
        y_adj = 0
        for i in range(0,turn_n):
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
                left_turns += 1
                addx, addy = rotate(np.pi, addx, addy)
                addx -= 2
                addy = addy[::-1]
                addy += y_adj + (y4[-1] - y[0])
            else:
                addy += y_adj
            rand = np.random.randint(4,7)
            if i < turn_n - 1:
                y_adj += (y4[-1] - y[0]) - straights[i]*s
            else:
                y_adj += (y4[-1] - y[0])

            x_list += addx.tolist()
            y_list += addy.tolist()

        x_list = [-1] + x_list + [-1]
        y_list = [10*s] + y_list + [y_list[-1] - 100*s]
        tracks.append([x_list, y_list])
        #with open('./res/tracks/track_{}_x.json'.format(track), 'w') as outfile:
        #    json.dump(x_list, outfile)
        #with open('./res/tracks/track_{}_y.json'.format(track), 'w') as outfile:
        #    json.dump(y_list, outfile)

    if (left_turns) == 100:
        break
print(left_turns)
with open('./res/tracks/all_tracks.json'.format(track), 'w') as outfile:
    json.dump(tracks, outfile)
plt.plot(np.array(y_list),np.array(x_list),  color = 'red')
#plt.axes().set_aspect('equal')
plt.show()
