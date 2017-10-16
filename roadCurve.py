import matplotlib.pyplot as plt
import numpy as np
from scipy.special import fresnel
import json
import math

x_list = []
y_list = []


def rotate(rad,x,y):
    x1 = math.cos(rad)*x - math.sin(rad)*y
    y1 = math.sin(rad)*x + math.cos(rad)*y
    return x1, y1

for i in range(0,20):
    t = np.linspace(0, (1/3.0)**0.5, 1000)
    x,y = fresnel(t)
    
    x -= x[0]
    y -= y[0] 

    arc = np.linspace(10/6.0 * math.pi, 11/6.0 * math.pi, 1000)
    x2 = np.cos(arc)
    y2 = np.sin(arc)
    x2 -= x2[0]
    y2 -= y2[0]
    y2 += x[-1]
    x2 += y[-1]

    x3 = x[::-1]
    y3 = y
    x3,y3 = rotate(-1*math.pi, x3,y3)
    x3 -= x3[0] - x2[-1]
    y3 -= y3[0] + y2[-1]
    y3 *= -1

    dist = y3[-1]

    if i % 2 == 0:
        y_list += (y + dist*i).tolist() + (x2 + dist*i).tolist() + (x3 + dist*i).tolist() 
        x_list += (x + dist*i).tolist() + (y2 + dist*i).tolist() + (y3 + dist*i).tolist() 
    else:
        x_list += (y + dist*i).tolist() + (x2 + dist*i).tolist() + (x3 + dist*i).tolist() 
        y_list += (x + dist*i).tolist() + (y2 + dist*i).tolist() + (y3 + dist*i).tolist() 



with open('road_euler_x.json', 'w') as outfile:
    json.dump(x_list, outfile)
with open('road_euler_y.json', 'w') as outfile:
    json.dump(y_list, outfile)


plt.plot(np.array(x_list)*50,np.array(y_list)*50,  color = 'red')
#plt.plot(np.array(y2),np.array(x2),  color = 'red')
#plt.plot(np.array(y3),np.array(x3),  color = 'red')
#plt.plot(np.array(x_list2),np.array(y_list2), color = 'red')
#plt.plot(np.array(x_list3),np.array(y_list3), color = 'red')
plt.axes().set_aspect('equal')
plt.show()

