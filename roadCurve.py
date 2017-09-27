import matplotlib.pyplot as plt
import numpy as np
from scipy.special import fresnel
import json

x_list = []
y_list = []

for i in range(10):
    t = np.linspace(0, 1, 1000)
    x,y = fresnel(t)
    x += i*(x[-1] - x[0])*2
    y = y*((-1)**(i % 2 + 1)) + 0.3*(i % 2)
    #print(y[-1]*200 - y[0]*200, y[0]*200)
    #print((x[-1] - x[0])*2, y[-1] - y[0])
    x_list += x.tolist() + (x*-1 + x[-1]*2).tolist()[::-1]
    y_list += y.tolist() + y.tolist()[::-1]



#with open('road_x.json', 'w') as outfile:
#    json.dump(x_list, outfile)
#with open('road_y.json', 'w') as outfile:
#    json.dump(y_list, outfile)

plt.plot(np.array(x_list)*200,np.array(y_list)*100, linewidth = 2)
#plt.plot(x*-1 + x[-1]*2,y, linewidth = 2)
#plt.plot([x[0], x[0]],[-5, y[0]], linewidth = 2)
plt.axes().set_aspect('equal')



x_list = []
y_list = []

for i in range(10):
    t = np.linspace(0, 2**0.5, 1000)
    x,y = fresnel(t)
    x += i*(x[-1] - x[0])*1
    y = y*((-1)**(i % 2 + 1)) + 0.3*(i % 2)
    #print(y[-1]*200 - y[0]*200, y[0]*200)
    #print((x[-1] - x[0])*2, y[-1] - y[0])
    x_list += x.tolist() # (x*-1 + x[-1]*2).tolist()[::-1]
    y_list += y.tolist() #+ y.tolist()[::-1]



with open('road_x.json', 'w') as outfile:
    json.dump(x_list, outfile)
with open('road_y.json', 'w') as outfile:
    json.dump(y_list, outfile)
plt.figure()
plt.plot(np.array(x_list)*200,np.array(y_list)*100, linewidth = 2)
#plt.plot(x*-1 + x[-1]*2,y, linewidth = 2)
#plt.plot([x[0], x[0]],[-5, y[0]], linewidth = 2)
plt.axes().set_aspect('equal')

x_list = []
y_list = []

for i in range(10):
    t = np.linspace(0, 1, 1000)
    x,y = fresnel(t)
    x += i*(x[-1] - x[0] + 0.15)*2
    y = y*((-1)**(i % 2 + 1)) + 0.1*(i % 2)
    #print(y[-1]*200 - y[0]*200, y[0]*200)
    #print((x[-1] - x[0])*2, y[-1] - y[0])
    x_list += x.tolist() + ((x*-1 + 0.1) + (x[-1] + 0.1)*2).tolist()[::-1]
    y_list += y.tolist() + y.tolist()[::-1]



#with open('road_x.json', 'w') as outfile:
#    json.dump(x_list, outfile)
#with open('road_y.json', 'w') as outfile:
#    json.dump(y_list, outfile)
plt.figure()
plt.plot(np.array(x_list)*200,np.array(y_list)*100, linewidth = 2)
#plt.plot(x*-1 + x[-1]*2,y, linewidth = 2)
#plt.plot([x[0], x[0]],[-5, y[0]], linewidth = 2)
plt.axes().set_aspect('equal')



plt.show()

