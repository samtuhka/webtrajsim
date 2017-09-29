import matplotlib.pyplot as plt
import numpy as np
from scipy.special import fresnel
import json




x_list = [0]
y_list = [0]

for i in range(10):
    t = np.linspace(0, 1, 1000)
    x,y = fresnel(t)
    
    x -= x[0]
    y -= y[0]

    x_list += (x + x_list[-1]).tolist()
    y_list += (y +  y_list[-1]).tolist()

    x_list += (y + x_list[-1]).tolist()
    y_list += (x + y_list[-1]).tolist()



with open('road_x.json', 'w') as outfile:
    json.dump(x_list, outfile)
with open('road_y.json', 'w') as outfile:
    json.dump(y_list, outfile)


plt.plot(np.array(x_list)*175,np.array(y_list)*175)
#plt.plot(x*-1 + x[-1]*2,y, linewidth = 2)
#plt.plot([x[0], x[0]],[-5, y[0]], linewidth = 2)
plt.axes().set_aspect('equal')
plt.show()

