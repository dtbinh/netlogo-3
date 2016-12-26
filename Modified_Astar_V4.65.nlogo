extensions [
  gis
  ]

globals [
  destination
  ]

breed [borders border]
breed [waypoints waypoint]
breed [nodes node]
breed [ships ship]
breed [banners banner]

patches-own [
  elev
  land
  cost
  reachable
  ]

ships-own [
  speed
  ship-distance
  totaltime
  last-patches
  ]

nodes-own [
  shipID
  nodetime
  shipspeed
]

;;;;;;;;;;;;;; setup ;;;;;;;;;;;;;
to setup
  ca
  draw-map
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; draw-map ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to color-map
  ask patches
  [
    ifelse elev >= 0
    [
      set pcolor scale-color green elev 0 2000
      if any? neighbors with [ elev < 0 ]
      [
        sprout-borders 1 [set size 0]
      ]
      set land true
    ]
    [
      set pcolor scale-color blue elev -3500 0
      set land false
    ]
    set reachable false
    set cost 0
  ]
end

to recolor-ocean
  ask patches with [land = false]
  [
    set pcolor scale-color blue elev -3500 0
    set reachable false
    set cost 0
  ]
end

to draw-map
  let data-source "UTM/raster_PM.asc"
  let elevation gis:load-dataset data-source
  let world (gis:envelope-of elevation)
  file-open data-source
  let n-cols read-from-string remove "ncols" file-read-line
  let n-rows read-from-string remove "nrows" file-read-line
  resize-world 0 n-cols 0 n-rows
  file-close
  if zoom != 1
  [
    let x0 (item 0 world + item 1 world) / 2
    let y0 (item 2 world + item 3 world) / 2
    let W0 zoom * (item 0 world - item 1 world) / 2
    let H0 zoom * (item 2 world - item 3 world) / 2
    set world (list (x0 - W0) (x0 + W0) (y0 - H0) (y0 + H0))
  ]
  gis:set-world-envelope-ds (world)
  gis:apply-raster elevation elev
  erase
  color-map
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; create (waypoints, obstacles & ships) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to place-waypoint
  if mouse-down?
  [
    ask patch mouse-xcor mouse-ycor
    [
      sprout-waypoints 1
      [
        set size 4
        set shape "circle"
        set color orange
      ]
    ]
    stop
  ]
end

to place-obstacle
  if mouse-down?
  [
    ask patch mouse-xcor mouse-ycor
    [
      set elev 100
      set pcolor black
      ask neighbors
      [
        set elev 100
        set pcolor black
      ]
    ]
  ]
end

to place-ships
  ask (turtle-set nodes ships) [die]
  ask waypoints with [patch-here != destination]
  [
    hatch-ships 1
    [
      let min-speed  max-speed * (1 - speed-variation)
      set speed min-speed + random-float (max-speed - min-speed)
      set ship-distance (speed * time-interval) / 3600 ; in kilometres
      output-show (word "Speed: " speed "km/h Ship-distance: " ship-distance " km every " time-interval " second")
      set totaltime 0
      set size 3
      set shape "boat top"
      set color red
      set pen-size 1
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; A* ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to label-destination
  erase
  ask waypoints with-max [who]
  [
    set destination patch-here
    set shape "star"
    set size 6
    hatch-banners 1
    [
      set size 0
      set label "Desination"
      set label-color red
      create-link-from myself
      [
        tie
        hide-link
      ]
      move-to one-of in-link-neighbors
      set heading 50
      fd 15
    ]
  ]
end

to find-shortest-path-to-ships
  label-destination
  if destination = 0
  [
    stop
  ]
  ask destination
  [
    set cost 0
    set pcolor gray
    set reachable true
    calculate-costs self
    if pcolor = red
    [
      find-exit 0
    ]
    ask patches with [land = false][set pcolor scale-color blue elev -3500 0]
  ]

  ask ships
  [
    ifelse [reachable = false] of patch-here
    [
      output-show (word "A path from the source to the destination does not exist." )
      die
    ]
    [
      output-show (word "distance to destination (absolute): " distance destination "km. Shortest Path Length: " [cost] of patch-here)
    ]
  ]
end

to find-exit [new-cost]
  let nextPatch 0
  ask self
  [
    set pcolor green
    set cost new-cost
    if any? neighbors with [pcolor = gray]
    [
      stop
    ]
    set nextPatch min-one-of neighbors with [reachable = true and pcolor != green] [cost]
    if nextPatch != nobody
    [
      ask nextPatch
      [
        find-exit new-cost + 0.1
      ]
    ]
  ]
end

to calculate-costs [source-patch]
  let current-patch 0
  let open []
  set open lput source-patch open
  let current-cost 0
  while [ length open != 0 ]
  [
    set current-patch item 0 open
    set open remove-item 0 open
    ask current-patch
    [
        set current-cost [cost] of current-patch + 1
        ask neighbors4 with [ land = false and elev <= min-depth and ( (pcolor != red and cost > current-cost) or reachable = false) ]
        [
          set pcolor gray
          set reachable true
          set open lput self open
          set cost current-cost
        ]
        set current-cost [cost] of current-patch + 1.4142
        ask neighbors with [ land = false and elev <= min-depth and ( (pcolor != red and cost > current-cost) or reachable = false) ]
        [
          set pcolor gray
          set reachable true
          set open lput self open
          set cost current-cost
        ]
        if any? neighbors with [ reachable = false ]
        [
          recalculate-cost current-patch
        ]
    ]
  ]
end

to recalculate-cost [border-patch]
  ask border-patch [
    let distance-to-land distance min-one-of borders [distance border-patch]
    ifelse distance-to-land < land-prox
    [
      set pcolor red
      set cost cost + (land-prox-weight * (land-prox - distance-to-land) / land-prox )
      expand-border
    ]
    [
      set pcolor blue
    ]
  ]
end

to expand-border
  let distance-to-land 0
  ask neighbors with [ pcolor = gray ]
  [
    set distance-to-land distance min-one-of borders [distance myself]
    if distance-to-land < land-prox
    [
      set pcolor red
      set cost cost + (land-prox-weight * (land-prox - distance-to-land) / land-prox )
      expand-border
    ]
  ]
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; MOVE ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to go
  reset-ticks
  place-ships
  while [any? ships with [patch-here != destination]][move]
  stop
end

to move
  tick
  let currentPatch 0
  let nextPatch 0
  ask ships with [patch-here != destination]
  [
    set currentPatch patch-here
    set nextPatch min-one-of neighbors with [reachable = true] [cost]
    if nextPatch = nobody
    [
      output-show (word "No route found!! ")
      die
      stop
    ]
    face nextPatch
    fd ship-distance
    if patch-here != currentPatch
    [
       if any? nodes-here with [shipID = [who] of myself and (nodetime + (100 * time-interval)) < [totaltime] of myself  ]
       [
         output-show (word "The ship has run aground, reduce the land-prox and/or land-prox-weight values ")
         die
         stop
       ]
       hatch-nodes 1 [
         set shipID [who] of myself
         set shipspeed [speed] of myself
         set nodetime [totaltime] of myself
       ]
    ]
    set totaltime totaltime + time-interval
    if patch-here = destination
    [
      output-show (word "Ship arrived after " (totaltime / 60) " minutes")
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; EXTRAS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to-report meters-per-patch
  let world gis:world-envelope ; [ minimum-x maximum-x minimum-y maximum-y ]
  let x-meters-per-patch (item 1 world - item 0 world) / (max-pxcor - min-pxcor)
  let y-meters-per-patch (item 3 world - item 2 world) / (max-pycor - min-pycor)
  report mean list x-meters-per-patch y-meters-per-patch
end

to export-shp
  let abc gis:turtle-dataset nodes
  let filename "NewRoute_"
  set filename (word filename "SS" land-prox "_" "W" land-prox-weight ".shp")
  gis:store-dataset abc filename
end

to erase
  reset-ticks
  ask banners [die]
  ask (turtle-set nodes ships) [die]
  ask waypoints [ set size 4 set shape "circle" set color orange ]
  recolor-ocean
end
@#$#@#$#@
GRAPHICS-WINDOW
280
10
951
439
-1
-1
1.0
1
10
1
1
1
0
0
0
1
0
660
0
397
0
0
1
ticks
30.0

BUTTON
10
30
100
63
setup / reset
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
10
155
195
191
export-shapefile
export-shp
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
105
30
192
105
find-path
find-shortest-path-to-ships
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
10
115
100
148
NIL
place-waypoint
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
10
360
130
393
land-prox-weight
land-prox-weight
0
10
1
.5
1
NIL
HORIZONTAL

INPUTBOX
10
290
70
350
land-prox
20
1
0
Number

BUTTON
105
115
195
148
NIL
place-obstacle
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
10
75
100
108
NIL
erase
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

INPUTBOX
10
220
70
280
min-depth
-50
1
0
Number

MONITOR
10
455
100
500
meters/patch
precision meters-per-patch 5
17
1
11

SLIDER
605
450
725
483
speed-variation
speed-variation
0
1
0
.1
1
NIL
HORIZONTAL

TEXTBOX
180
200
255
218
Ship Variables
11
0.0
1

TEXTBOX
10
440
160
460
World Variables
11
0.0
1

TEXTBOX
15
10
165
28
Procedures
11
0.0
1

TEXTBOX
15
200
165
218
A* Variables
11
0.0
1

SLIDER
830
450
950
483
min-ship-distance
min-ship-distance
0
2
1
.1
1
NIL
HORIZONTAL

TEXTBOX
135
210
150
416
|\n|\n|\n|\n|\n|\n|\n|\n|\n|\n|\n|\n|\n|\n|\n
11
0.0
1

BUTTON
200
30
270
105
move
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

INPUTBOX
145
220
215
280
max-speed
80
1
0
Number

SLIDER
280
445
440
478
zoom
zoom
0.1
1
1
.1
1
NIL
HORIZONTAL

MONITOR
110
455
180
500
minutes
( ticks * time-interval ) / 60
5
1
11

INPUTBOX
145
290
215
350
time-interval
1
1
0
Number

TEXTBOX
220
255
250
273
km/h
11
0.0
1

TEXTBOX
220
330
270
356
seconds
11
0.0
1

@#$#@#$#@
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;TO DO NOTES;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

***adjust the cell size to make the meters per patch accurate. it currently get mean cell size which is false.  BY doing this must define the world in different x and y cell size to account for the shape of the earth. this can be best accomplised by dling raster/shapefiles of port metro with a projection that matches the area as opposed to wgs 1984. because if changed cell size in prj of asc it wont match up with shp***















;;;;;;;;;;;;;;;FOR SHIP MOVEMENT ONLY (NO RULES FOR SHIP-SHIP ENCOUNTERS);;;;;;;;;;;;;;;

min distance from land (must be min distane to stay away from shorelines and in center                           of waterway)

obey-elevation (must stay below certain elevation in order to avoid groundings)


current-waypoint (identifies where ship currently is- so their target destination is not                        identified as current location)

target-waypoint (identifies the destination they are trying to reach)


target-waypoint-distance (must decrease in order to reach target)

path-restrictions (dont go to patches where ship was previously)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; SHIP DEFAULT PARAMETERS ;;;;;;;;;;;;;;;;;;;;;;;;;;;

speed (set speed variable with min speed and max speed)

size (set given size and have larger ships take priority)

current & target-waypoints ( to help ship identify where is and where to go)

;;;;;;;;;;;;;;;;;;;;;;;;;SHIP TO SHIP ENCOUNTERS RULES TO APPLY ;;;;;;;;;;;;;;;;;;;;;;;;;

slow-down- when in an encounter with other ships slowdown and change direction to allow for faster ship to over-pass.

change-direction - if other ship in certain radius set heading right (potentially        change angle and direction of adjustment based on other ships position)

over-pass - if ship with higher velocity behind move right (45 not 90) and reduce        velocity






******************************

need to know how fast the ship is going
must incoprate speed to the ships then advance the tick counter by the amount of time it would take for a ship to travel 1 patch (depending on zoom (meters per patch))
tickadvance * speed/mpp or something

asume ship speed 40 km/h
assume 1000 meters per patch

(mpp/1000)




fuel consumption graph

ship-ship interaction

head-on

overtake



THINGS TO FIGURE OUT
**** change speed of ships in simulation not just as variable

***** allow ships to divert from current path and return to closest point in the list



possible scenarios for ship interaction

using heading, ship direction, speed, ship prox


OVER_PASS
same heading, within given prox and ship is ahead(using ship direction), ovetake if speed of other ship is less, if speed is same more slightly less (less than 2 km/h) or the same then slow down and allow ship to maintain distance from ship in front.


WAIT
direction ahead of ship, heading greater than 20 degree distance wait untill ship moves to continue(ship that is moving slower)

HEAD_TO_HEAD
direction ahead, ship moving in opposite or close to opposite heading, allow ships to both move one space to the right one space forward and then back to the nearest point on the current path (by erasing patch it wouldve went on prior to avoidance) then towrds the new lowest patch in path.






 tick count is not accurate as it counts the amount of steps at current speed + a tick everytime it has to jump from distance < 0.1 in order to land directly on space in path to remove it from the list and move on to the next one.  Could say if the distance to the exact path location is less than 1 than move to the next..? that way it wont run a step everytime it needs to land directly on the whole number.







CURRENT


list adds up total time
time is based of distance of each step/ speed\
need to cfind right scale so time matches up Check this by making max speed same as path length reducing variation to 0, and time traveled should be 1 hour



HELP
I have tried several methods of measuring the time it takes for a turtle (in my case ships) to travel a set distance at a desired speed.  Currently I have the turtles moving (through a list of coordinates) a set distance each tick based on its 'speed' value, the scale of the world/map, and the time interval for each tick. However once it reaches a distance (to the next coordinate on the list) that is less than the distance it is required to move in each tick, the ship will jump to the coordinate and it should calculate the appropriate weight in order to add the correct fraction of time to the total time required to travel said distance.
Needless to say, it is not working correctly and with my limited netlogo knowledge I need some help finding a solution. I would imagine someone with a better understanding should be able to spot the issue and fix it without much grief.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

boat
false
0
Polygon -1 true false 63 162 90 207 223 207 290 162
Rectangle -6459832 true false 150 32 157 162
Polygon -13345367 true false 150 34 131 49 145 47 147 48 149 49
Polygon -7500403 true true 158 33 230 157 182 150 169 151 157 156
Polygon -7500403 true true 149 55 88 143 103 139 111 136 117 139 126 145 130 147 139 147 146 146 149 55

boat 2
false
0
Polygon -1 true false 63 162 90 207 223 207 290 162
Rectangle -6459832 true false 150 32 157 162
Polygon -13345367 true false 150 34 131 49 145 47 147 48 149 49
Polygon -7500403 true true 157 54 175 79 174 96 185 102 178 112 194 124 196 131 190 139 192 146 211 151 216 154 157 154
Polygon -7500403 true true 150 74 146 91 139 99 143 114 141 123 137 126 131 129 132 139 142 136 126 142 119 147 148 147

boat 3
false
0
Polygon -1 true false 63 162 90 207 223 207 290 162
Rectangle -6459832 true false 150 32 157 162
Polygon -13345367 true false 150 34 131 49 145 47 147 48 149 49
Polygon -7500403 true true 158 37 172 45 188 59 202 79 217 109 220 130 218 147 204 156 158 156 161 142 170 123 170 102 169 88 165 62
Polygon -7500403 true true 149 66 142 78 139 96 141 111 146 139 148 147 110 147 113 131 118 106 126 71

boat top
true
0
Polygon -7500403 true true 150 1 137 18 123 46 110 87 102 150 106 208 114 258 123 286 175 287 183 258 193 209 198 150 191 87 178 46 163 17
Rectangle -16777216 false false 129 92 170 178
Rectangle -16777216 false false 120 63 180 93
Rectangle -7500403 true true 133 89 165 165
Polygon -11221820 true false 150 60 105 105 150 90 195 105
Polygon -16777216 false false 150 60 105 105 150 90 195 105
Rectangle -16777216 false false 135 178 165 262
Polygon -16777216 false false 134 262 144 286 158 286 166 262
Line -16777216 false 129 149 171 149
Line -16777216 false 166 262 188 252
Line -16777216 false 134 262 112 252
Line -16777216 false 150 2 149 62

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

factory
false
0
Rectangle -7500403 true true 76 194 285 270
Rectangle -7500403 true true 36 95 59 231
Rectangle -16777216 true false 90 210 270 240
Line -7500403 true 90 195 90 255
Line -7500403 true 120 195 120 255
Line -7500403 true 150 195 150 240
Line -7500403 true 180 195 180 255
Line -7500403 true 210 210 210 240
Line -7500403 true 240 210 240 240
Line -7500403 true 90 225 270 225
Circle -1 true false 37 73 32
Circle -1 true false 55 38 54
Circle -1 true false 96 21 42
Circle -1 true false 105 40 32
Circle -1 true false 129 19 42
Rectangle -7500403 true true 14 228 78 270

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

rectangle
true
0
Rectangle -7500403 true true 105 15 210 285

sailboat side
false
0
Line -16777216 false 0 240 120 210
Polygon -7500403 true true 0 239 270 254 270 269 240 284 225 299 60 299 15 254
Polygon -1 true false 15 240 30 195 75 120 105 90 105 225
Polygon -1 true false 135 75 165 180 150 240 255 240 285 225 255 150 210 105
Line -16777216 false 105 90 120 60
Line -16777216 false 120 45 120 240
Line -16777216 false 150 240 120 240
Line -16777216 false 135 75 120 60
Polygon -7500403 true true 120 60 75 45 120 30
Polygon -16777216 false false 105 90 75 120 30 195 15 240 105 225
Polygon -16777216 false false 135 75 165 180 150 240 255 240 285 225 255 150 210 105
Polygon -16777216 false false 0 239 60 299 225 299 240 284 270 269 270 254

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

thin ring
true
0
Circle -7500403 false true -1 -1 301

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.3.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
1
@#$#@#$#@
