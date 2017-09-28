![smallplanet_Pinball](/meta/logo.png?raw=true "smallplanet_Pinball")

# Overview

An experiment in using machine vision, deep learning, and CoreML to allow an iPhone to play a real pinball machine. We believe that intelligently driving a pinball machine will provide several unique challenges to deep (Q)-learning not present in experiments on digital game systems. For example, since the only input into the system is from the device's camera, the whole system from hardware, software, training, to playback must be fast enough to handle the hectic pace of pinball in real-time, whereas a computer emulator can be stepped through at a much slower, more regulated pace.


#  The Machines

* **Nascar** by Stern Pinball
* **Stargate** by Gottlieb
* **Star Trek: The Next Generation** by Williams Electronics

#  Rules

We allow ourselves the ability to modify the machine for the purposes of providing input only. For example, we can use hardware relays to drive the left/right flippers.  

We chose not allow ourselves to instrument any output from the machine. For example if we wanted to utilize the player's score then we need to read it visually off of the machine's display instead of providing it electronically to the app.

#  Roadmap

### Phase 0
Utilize an Omega2 to allow networked control of the pinball machine

1. ~~flip left and right flippers~~
2. ~~press the start button~~
3. ~~activate the ball kicker~~

### Phase 1
Implement supervised learning such that the AI can intelligently hit the pinball with the flippers

1. ~~capture mode to gather training images of human playing~~
3. ~~create and train model using keras~~
4. ~~play mode to feed camera images to CoreML and activate flippers~~
5. ~~activate the ball kicker~~
6. ~~activate the start button~~

### Phase 2
Implement unsupervised learning/Deep Q-Learning such that the AI can play well

1. train model to read score off of the machine's display
2. provide a play & capture mode to flip the flippers while capturing training material
3. perform continuous learning on a machine on the same network as the app (ie don't attempt to train on the phone)
4. upload new CoreML models dynamically


# Cool stuff

*Omega2 board is connected to the flippers in the machine*  
![smallplanet_Pinball](/meta/omega.jpg?raw=true "Omega2 connected to machine")

*iPhone is suspended above Nascar machine providing full view of the playing field*  
![smallplanet_Pinball](/meta/iphone.jpg?raw=true "iPhone rig")

*90 frames from a 220k frame training set*  
![smallplanet_Pinball](/meta/training.gif?raw=true "Training sample")

*Phase 1 model playing Nascar pinball*  
![smallplanet_Pinball](/meta/clip_high.gif?raw=true "Phase 1 Nascar model")

## License

This is free software distributed under the terms of the MIT license, reproduced below. This may be used for any purpose, including commercial purposes, at absolutely no cost. No paperwork, no royalties, no GNU-like "copyleft" restrictions. Just download and enjoy.

Copyright (c) 2017 [Small Planet Digital, LLC](http://smallplanet.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
