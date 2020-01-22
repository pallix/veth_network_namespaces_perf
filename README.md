# Veth performance problems

Illustrate some performance problem with the Linux `veth` interface.

Tested on a `m5.2xlarge` AWS EC2 instance.

## Reproducing

Create several Linux network namespaces:

```
for i in $(seq 1 1000); do (sudo ./create-net-ns.sh $i &); done
```

Then start several `socat` server:

```
for i in $(seq 1 1000); do (sudo ./start-socat.sh $i &); done
```

Then start to send data on the first 500 servers (~7kb per second per server):

```
for i in $(seq 1 500); do (sudo ./send-data.sh $i &); done
```

Go into the first network namespace:

```
sudo ip netns exec sim1 bash
```

Then start to monitor how long a connection takes to be created:

```
# in sim1
while true; do date ; time nc -zv 10.11.0.3 1883; sleep 1; done
```

Start to send data on the next 200 servers:

```
for i in $(seq 501 700); do (sudo ./send-data.sh $i &); done
```

After a bit of time, the monitoring show that connections are created very slowly (> 1 second)

```
real	0m3.075s <-- too slow
user	0m0.000s
sys	0m0.000s
```

and connections timeouts errors are produced by socat (from the `send-data.sh` script):

```
socat[2226] E connect(5, AF=2 10.11.2.80:1883, 16): Connection timed out
```
