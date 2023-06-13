# Membrane LiveFilter Plugin
The Membrane.Realtimer filter is component used to emit buffers in realtime. There are two things
that did not work out for us and made us create our own realtimer:
- in our pipeline, the world does not start from 0 but rather from the first decoded PTS, which usually comes
from an RTMP stream which we connected to after it started. Say the stream's playback is 2 hours. Membrane's Realtimer
will wait 2 hours before emitting the first packet
- after updating to membrane_core 0.11, we noticed that the realtimer was not ticking at the expected rate in wierd ways. We have not dedicated enough time to understand the issue, but using this code which does not provide the clock synchronization features that Membrane's Realtimer provides worked as expected.

This element is used in production.

## Installation
```elixir
def deps do
  [
    {:membrane_live_filter_plugin, github: "kim-company/membrane_live_filter_plugin"}
  ]
end
```
## Copyright and License
Copyright 2023, [KIM Keep In Mind GmbH](https://www.keepinmind.info/)
Licensed under the [Apache License, Version 2.0](LICENSE)
