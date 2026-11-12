# Auto

Auto keeps the connection on a server from the chosen subscription and switches only when the current server stops responding. A faster server showing up is not a reason to switch: as long as the current one responds, the app stays on it.

Auto can be on in only one subscription at a time. When you turn it on, the app picks the server with the best score (more on that below) and, if the VPN is connected, reconnects to it.

## Server score

To pick a server, Auto gives each one a score based on its recent measurements. The score has three parts:

- the server's typical ping;
- how much the ping jumps between measurements;
- 1000 for every measurement the server didn't answer.

The server with the lowest score wins. The score doesn't say whether a server works, it sets the queue: all servers in the subscription line up by score, and Auto takes the first one.

For example, three servers each have three recent measurements:

| Server | Measurements, ms | Typical ping | Jumps by | No answer | Score |
|---|---|---|---|---|---|
| Finland | 60, 61, 62 | 61 | 2 | 0 times | **63** |
| Germany | 20, 25, 300 | 25 | 280 | 0 times | 305 |
| Netherlands | 15, 18, no answer | 18 | 3 | 1 time | 1021 |

Auto picks Finland. Germany's best measurement is faster, but its ping jumps a lot. The Netherlands is the fastest, but it failed to answer once.

Servers without a ping go after the scored ones: first those with a speed test result (fastest first), then those never checked, and last those whose latest measurement got no answer. With equal scores the subscription order is kept.

::: details Exact definition
A server keeps its last 5 measurements. The score uses those made with the same method as the latest one (TCP, URL or ICMP) and no older than 24 hours. Let $r_1 \le r_2 \le \dots \le r_n$ be the delays of the answered measurements in milliseconds, and $f$ the number of measurements with no answer. Then

$$
S =
\begin{cases}
\tilde r + (r_n - r_1) + 1000 \cdot f, & n \ge 2 \\
r_{\text{last}} + 1000 \cdot f, & n < 2
\end{cases}
$$

where $\tilde r$ is the median (“typical ping”; for even $n$ the larger of the two middle values is taken), $r_n - r_1$ is the spread (“jumps by”), and $r_{\text{last}}$ is the result of the latest measurement.
:::


## When a check starts

<AutoCycle />

While the VPN is on, the app watches the traffic. A check starts if:

- data goes out but nothing comes back for 2 seconds in a row (5 seconds on a computer);
- the core couldn't connect to the server;
- nothing came in for 30 seconds even though something was sent;
- 5 minutes have passed since the last scheduled check and there was traffic during that time. While nobody is using the device, Auto leaves the servers alone.

On Android a check doesn't start if the phone has no network at all right now.

## How a check works

The app checks the current server and up to 9 servers with the best scores from the same subscription, the same way [HTTP ping](/en/ping) does. A scheduled check looks at fewer servers: the current one, the server to switch back to, and a couple of the best ones.

- The current one answered: the app stays on it, even if another server answered faster.
- The current one didn't answer but others did: the app switches to the answering server with the best score.
- Nobody answered: the app asks the neighboring subscriptions, more on that below.

When switching, the score is calculated the same way, except the ping from this check replaces the typical ping. So a server that answered quickly just now but jumped around all day still loses to a steady one.

::: details Exact definition
Let $L$ be the server's ping in this check, $A$ the set of $L$ and the server's answered measurements over 24 hours, and $f$ the number of measurements with no answer over the same time:

$$
S' = L + (\max A - \min A) + 1000 \cdot f
$$
:::

If the selected server disappears from the subscription after an update, Auto immediately puts the best of the remaining ones in its place and reconnects.

## When the whole subscription is silent

One subscription alone can't tell you whether its servers went down or the network dropped. So the app asks the neighbors: the 2 best servers from the nearest subscription above and from the nearest one below in the list.

**The neighbors are silent too.** Then the network is gone. The app stays on the server and doesn't record these measurements in the history, otherwise after a ride in an elevator the best servers would carry a penalty for a whole day. The next attempt comes after

$$
T_k = \min\left(15 \cdot 2^{\,k-1},\ 120\right) \text{ s},
$$

where $k$ is the attempt number in a row: 15, 30, 60 seconds, then every 2 minutes. On Android a network change, for example from mobile data to Wi-Fi, ends the pause right away.

**The neighbors answer.** Then the network is fine and your own subscription is down. The next check looks at it more widely, up to 30 servers. If the subscription is still silent (that check comes within 5 minutes at most), Auto switches to the best server of the neighboring subscription.

## Switching back

When leaving a server, the app remembers it. Scheduled checks look at it too, and if it answers twice in a row, Auto switches back to it.

While you're on a server from a neighboring subscription, your own subscription is checked once a minute. After 5 failures in a row these checks pause for 15 minutes, so the app doesn't keep measuring servers for your whole subway ride.

## Limits

- No more than 3 switches in 3 minutes. If servers go down one after another, the app doesn't hop around in circles, it waits.
- No new check starts for 5 seconds after a switch and for 15 seconds after a regular check: the reconnect itself looks like a failure for a couple of seconds.

## Servers that Auto skips

Press and hold the “Auto” button to mark servers that Auto won't switch to. On Android TV hold OK on the remote, with a mouse use the right button.

- You can't mark the last unmarked server.
- If after an update only marked servers remain in the subscription, Auto picks from them.
- If you mark the server you're connected to, after “Done” the app switches to the best of the rest.

Marks are kept when the subscription updates.
