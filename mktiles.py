#!/usr/bin/python3

import sys
import psycopg2
import os
import time
import threading
import queue
printer_lock=threading.Lock()

dbaccess,z,x,y,outdir=sys.argv[1:]
format='pbf'

z=int(z)
xs=[x]
ys=[y]
if x=='*' :
    xs=list(range(2**z))
if y=='*' :
    ys=list(range(2**z))
if x.find('-')>=0 :
    xs=list(range(*map(int,x.split('-'))))
if y.find('-')>=0 :
    ys=list(range(*map(int,y.split('-'))))

class Writer(threading.Thread) :
    def __init__(self,c) :
        threading.Thread.__init__(self)
        self.c=c
        self.finished=False
        self.todo=queue.Queue(100)
        self.total_written=0
        self.total_count=0

    def run(self) :
        while True :
            z,x,y=self.todo.get(block=True)
            #check end sentinel
            if z==None :
                #but also check no more work to do
                if self.finished and self.todo.empty() :
                    break
                # else finish processing everything, but still keep sentinel in mind
                self.todo.put((None,None,None))
                continue # skip processing the None
            self.process(z,x,y)

    def join(self) :
        self.finished=True
        #end sentinel
        self.todo.put((None,None,None))
        threading.Thread.join(self)

    def process(self,z,x,y) :
        self.c.execute(self.c.mogrify('SELECT omt_all(%s,%s,%s);',(z,x,y)))
        if not os.path.exists(f'{outdir}/{z}/{x}') :
            os.makedirs(f'{outdir}/{z}/{x}')
        with open(f'{outdir}/{z}/{x}/{y}.{format}','wb') as f:
            bs_written=f.write(self.c.fetchone()[0])
        self.total_written+=bs_written
        self.total_count+=1
        with printer_lock :
            print(f'{z}/{x}/{y}.{format}',bs_written,'bytes')


access=psycopg2.connect(sys.argv[1])
ts=[Writer(access.cursor()) for i in range(5)]

start=time.time()
[t.start() for t in ts]
tix=0
for x in xs :
    for y in ys :
        ts[(tix)%len(ts)].todo.put((z,x,y))
        tix+=1

[t.join() for t in ts]

total_bytes=sum(t.total_written for t in ts)
total_count=sum(t.total_count for t in ts)
print(round(total_bytes*1e-6,2),'MB total')
print('average tilesize',round(total_bytes/total_count*1e-3,2),'KB,',total_count,'tiles')
print(round(time.time()-start,1),'seconds')
