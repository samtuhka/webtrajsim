import matplotlib.pyplot as plt
import numpy as np
from scipy.special import fresnel
import json
import math


dist = 0

x_list = []
y_list = []

x_adj = 0
y_adj = 0

def curve(start, end, xad = 0, yad = 0, order = 1):
    arc = np.linspace(start, end, 1200)
    x = np.cos(arc) + xad
    y = np.sin(arc) + yad
    return x[::order], y

def rotate(rad,x,y):
    x1 = math.cos(rad)*x - math.sin(rad)*y
    y1 = math.sin(rad)*x + math.cos(rad)*y
    return x1, y1

dur = 0.75
speed = 30

for i in range(0,20):
    s = (2*np.pi)/(360/speed)*dur

    c = (speed/360*dur)*np.pi
    x,y = curve(np.pi, np.pi + c, 0)
    x2,y2 = curve(c,0, -2*np.cos(c),  -np.sin(c)*2)
    r = s

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
    rand = np.random.randint(5,10)
    y_adj += (y4[-1] - y[0]) - rand*s

    x_list += addx.tolist()
    y_list += addy.tolist()

x_list = [-1] + x_list + [-1]
y_list = [10*s] + y_list + [y_list[-1] - 10*s]

with open('road_beech_x.json', 'w') as outfile:
    json.dump(x_list, outfile)
with open('road_beech_y.json', 'w') as outfile:
    json.dump(y_list, outfile)

plt.plot(np.array(x_list),np.array(y_list),  color = 'red')
#plt.axes().set_aspect('equal')
plt.show()
