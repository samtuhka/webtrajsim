import numpy as np
import sys
import os
import msgpack
import gzip

def loadSession(f, sid):
    data = list(msgpack.Unpacker(f, encoding='utf-8'))

    scenarioStarts = [(0, 'startup')]
    for i, row in enumerate(data):
        name = row['data'].get('loadingScenario')
        if name is None:
            continue
        scenarioStarts.append((i, name))
    
    scenarioStarts.append((None, None))
    
    scenarioLogs = []
    
    for i in range(len(scenarioStarts)-1):
        start, name = scenarioStarts[i]
        end, dummy = scenarioStarts[i+1]
        scenarioLogs.append((data[start:end], sid, i, name))
    return scenarioLogs

def trialToNumpy(data, sid, block, experiment):
    positions = []
    glanceTimes = []
    trialStartTime = None
    prevTime = None
    isBlind = False
    throttle = 0
    brake = 0
    for row in data:
        ts = row['time']
        if trialStartTime is None:
            trialStartTime = ts
        d = row['data']

        if 'blinder' in d:
            isBlind = d['blinder']

        if 'telemetry' in d:
            throttle = d['telemetry']['throttle']
            brake = d['telemetry']['brake']

        if 'physics' not in row['data']:
            continue
        pos = {}
        #pos['ts'] = ts
        pos['ts'] = row['data']['physics']['time']
        prevTime = pos['ts']
        for body in row['data']['physics']['bodies']:
            if body.get('objectClass') != 'vehicle':
                continue
            if body.get('objectName') == 'player':
                pos['player'] = body['position']['z']
            else:
                pos['leader'] = body['position']['z']
        
        
        positions.append([sid, block, experiment, pos['ts'], pos['player'], pos.get('leader', np.nan), row['time'], isBlind, throttle, brake])
    
    if len(positions) == 0:
        return None
    positions = np.rec.fromrecords(positions, names='sessionId,block,experiment,ts,player,leader,absTs,blind,throttle,brake')
    # There's a bug in the simulator that causes the ts to increment
    # twice. Correct it here, so it's right for the analysis scripts.
    positions['ts'] /= 2.0
    return positions

def rowstack(arrays):
    # Just like hstack, but makes sure that
    # different length string fields can be concatenated
    dtypes = [a.dtype for a in arrays]
    dtype = []
    # Dtypes won't do zip :(
    for name in arrays[0].dtype.names:
        cols = [dt[name] for dt in dtypes]
        dtype.append((name, max(cols)))
    dtype = np.dtype(dtype)
    arrays = [np.asarray(a, dtype=dtype) for a in arrays]
    return np.hstack(arrays)


def sessionToNumpy(path):
    data = []
    sid = os.path.basename(path)
    for trial in loadSession(gzip.open(path), sid):
        d = trialToNumpy(*trial)
        if d is None:
            continue
        data.append(d)

    data = rowstack(data)
    return data
   

def main(paths=sys.argv[1:]):
    data = []
    for path in paths:
        data.append(sessionToNumpy(path))

    data = rowstack(data)
    np.save(sys.stdout, data)
    return data

if __name__ == '__main__':
    main()
