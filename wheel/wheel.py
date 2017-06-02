#!/usr/bin/env python3
from __future__ import division
import evdev
from evdev import ecodes
from pprint import pprint
import sys
import json
import threading
import logging

def probe_wheel():
    for dev in map(evdev.InputDevice, evdev.list_devices()):
        nabs = len(dev.capabilities().get(ecodes.EV_ABS))
        if nabs >= 3:
            return dev
    raise SystemError("No wheel found")

def run_gk25(outf=sys.stdout, inf=sys.stdin):
    dev = probe_wheel()
    
    class Feedback:
        def autocenter(self, value):
            value = int(value*100)
            evdev._uinput.write(dev.fd, ecodes.EV_FF, ecodes.FF_AUTOCENTER, 0xFFFF*value//100)
    feedback = Feedback()

    axes = dev.capabilities().get(ecodes.EV_ABS)
    def normer(o, n):
        olow, ohigh = o
        low, high = n
        a = (high - low)/(ohigh - olow)
        b = high - a*ohigh
        def scaler(ev):
            return ev.value*a + b
        return scaler
    
    mapping = {}
    def mapAxis(code, name, newrng, orng=None):
        wtf, info = axes[code]
        if orng is None:
            orng = (info.min, info.max)
        mapping[(ecodes.EV_ABS, code)] = dict(name=name, normer=normer(orng, newrng))

    def mapKey(code, name):
        mapping[(ecodes.EV_KEY, code)] = dict(name=name, normer=lambda ev: bool(ev.value))

    FRONT_LEFT_KEY = 297 # Not defined in linux/input.h
    FRONT_RIGHT_KEY = 296 # Not defined in linux/input.h
    BACK_LEFT_KEY = 293 # Not defined in linux/input.h
    BACK_RIGHT_KEY = 292 # Not defined in linux/input.h
    A = 288
    Xbox = 298
    mapAxis(ecodes.ABS_X, "steering", (1, -1))
    mapAxis(ecodes.ABS_Y, "throttle", (1, 0))
    mapAxis(ecodes.ABS_Z, "brake", (1, 0), (0, 255))
    mapKey(FRONT_RIGHT_KEY, "catch")
    mapKey(FRONT_LEFT_KEY, "frontLeft")
    mapKey(BACK_RIGHT_KEY, "backRight")
    mapKey(BACK_LEFT_KEY, "blinder")
    mapKey(A, "A")
    mapKey(Xbox, "Xbox")
    
    
    def handlemsg(msg):
            msg = json.loads(msg)
            for name, value in msg.items():
                getattr(feedback, name)(value)

    def readloop():
        for line in inf:
            try:
                handlemsg(line)
            except Exception as e:
                logging.error(e)
    threading.Thread(target=readloop).start()
    
    def sendloop():
        for event in dev.read_loop():
            tc = (event.type, event.code)
            #logging.warning(tc)
            if tc not in mapping: continue
            axis = mapping[tc]
            msg = {}
            msg[axis['name']] = axis['normer'](event)
            json.dump(msg, outf)
            outf.write('\n')
            outf.flush()
    sendloop()

#pprint(dir(ecodes))
#help(ecodes)
run_gk25()
