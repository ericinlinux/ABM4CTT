extensions [ gis ]

;; --------------------------------
;;      GLOBALS
;; -------------------------------

globals [
  ; map globals
  buildings-dataset
  roads-dataset
  destination-patch       ;; auxiliar to find the vertex closest to the patch
  min-ticks-wait          ;; min time of wait after a person gets to their destination
  max-ticks-wait          ;; max time of wait after a person gets to their destination
  popular-times           ;; percentage of people active over time slots of 1h
  offenders-popular-times ;; percentage of offenders active over time slots of 1h
  crime-rates-per-hour    ;; vector with the percentage of crimes ocurred by 1h slot
  cur-day                 ;; day
  cur-hour                ;; hour
  cur-min                 ;; min
  week-day                ;; day of the week
  prob-standby            ;; probability of an agent to go standby
  total-crimes            ;; count of the crimes

  #-vertices
  report-crimes-per-hour  ;; vector to report the crimes per hour
]

;; --------------------------------
;;      NEW BREEDS
;; -------------------------------
breed [ vertices vertex ]
vertices-own [
  myneighbors ;; agentset of neighbouring vertices
  test

  ;; variables used in path-selection function
  dist        ;; distance from the original point to here
  done        ;; 1 if has calculated the shortest path through this point, 0 otherwise
  lastnode    ;; last node to this point in shortest path

]

breed [ people person ]
people-own [
  destination       ;; next vertex to go
  mynode            ;; current node
  active?           ;; after node reaches destination, it stays there for a while
  ;time-standby      ;; time the agent will stay in the destination before moving again
  home-vertex       ;; home vertex
  ;; OFFENDERS VARIABLES
  offender?         ;; if the node is an offender
  crimes-committed  ;; number of crimes committed
  victim            ;; potential victim selected
  motivation
  ;; CITIZENS VARIABLES
  awareness         ;; awareness level of the agent
  victim-history    ;; if the person was a victim recently, this variable is gonna be higher
  robbed?           ;; if the person was robbed
  gender            ;; 0 male 1 female
  age               ;; age of the agent
]

patches-own [
  corner?        ;; if path is one of the corner streets
  closest-vertex ;; the closest vertex of the corner patches (only for corner patches)
  ;; MODEL VARIABLES
  num-people-here   ;; number of people (no offenders) in a patch
  density           ;; amount of people in the node
  crime-hist-vertex ;; if there was a crime in this vertex recently
  attractiveness    ;; overall attractiveness of the location
  time-effect       ;; time of the day effect
  crimes-in-vertex  ;; total crimes in the vertex


]

;; --------------------------------
;;      SETUP PROCEDURES
;; -------------------------------
to setup
  ca
  setup-map
  ; setup graph
  setup-vertices
  setup-globals
  setup-citizens

  reset-ticks
end


;; GLOBALS
to setup-globals
  ;; set min-ticks-wait 1   ;; every tick is 10 minutes
  ;; set max-ticks-wait 24  ;; 4 hours max
  ;; set popular-times [ 10 2 1 1 1 2 10 15 20 40 80 100 100 80 70 60 70 80 100 80 50 40 30 20 ]
  ;; set offenders-popular-times [ 90 90 80 70 40 20 10 5 5 10 20 30 30 30 30 50 50 50 60 60 70 70 70 80 ]

  set cur-day 0          ;; starts on day 0
  set cur-hour 0
  set cur-min 0
  set crime-rates-per-hour [13 13 19 19 9 9 2 2 1 1 3 3 5 5 4 4 4 4 9 9 25 25 19 19]
  set report-crimes-per-hour [0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 ]

  set #-vertices count vertices
  set num-people 10000
  set num-offenders 20
  set motivation-sf 0.01
  set awareness-sf 0.5
  ;set victim-history 0.1
end

;; MAP READING
to setup-map
  ; size of the patch map
  resize-world -180 180 -115 115
  set-patch-size 1.5
  ask patches [ set pcolor white ]

  ; Load all of our datasets
  set buildings-dataset gis:load-dataset "../data/buildings2.shp"
  set roads-dataset gis:load-dataset "../data/roads.shp"
  ; Set the world envelope to the union of all of our dataset's envelopes
  gis:set-world-envelope (gis:envelope-union-of (gis:envelope-of buildings-dataset)
                                                (gis:envelope-of roads-dataset))

  ; display buildings
  if show-buildings = True [
    ; display roads
    gis:set-drawing-color gray
    gis:draw roads-dataset 1

    gis:set-drawing-color blue
    gis:draw buildings-dataset 1
  ]
end


;; ROAD NETWORK CREATION
; following example 8.4.2
to setup-vertices
  foreach gis:feature-list-of roads-dataset [
    road-feature ->
    ;; for the road feature, iterate over the vertices that make it up
    foreach gis:vertex-lists-of road-feature [
      v ->
      let previous-node-pt nobody ;; previous node is used to link nodes together
      ;; for each vertex, iterate over its individual points
      foreach v [
        node ->
        ;; find the location of the node and create a new vertex agent there
        let location gis:location-of node
        if not empty? location [
          create-vertices 1 [
            set myneighbors n-of 0 turtles ;; empty
            set xcor item 0 location
            set ycor item 1 location
            ask patch item 0 location item 1 location [ ;; defining the street corners
              set corner? true
            ]
            set size 2
            set shape "circle"
            set color red
            set hidden? true

            ;; create a link to the previous node
            ifelse previous-node-pt = nobody [
              ;; first vertex in feature, so do nothing
            ][
              create-link-with previous-node-pt ;; create link to previous node
            ]
            ;; remember THIS node so that the next one can link back to it
            set previous-node-pt self
          ]
        ]
      ]
    ]
  ]

  ;; delete duplicate vertices (there may be more than one vertice on the same patch due
  ;; to reducing size of the map). Therefore, this map is simplified from the original map.
  delete-duplicates
  ask vertices [set myneighbors link-neighbors]
  delete-not-connected
  ask vertices [set myneighbors link-neighbors]




  ask patches with [ corner? = true ][
    set closest-vertex min-one-of vertices in-radius 50 [distance myself]
    ;; initiate the variables for attractiveness
    set attractiveness 0
    set crime-hist-vertex 0
  ]

  ask links [set thickness 1.4 set color black]
end

to setup-citizens
  create-people num-people [
    set shape "person"
    set size 5
    set color green

    set destination nobody
    ;set last-stop nobody
    set active? true
    set mynode one-of vertices move-to mynode
    set home-vertex mynode

    ; for citizens
    set robbed? false
    set victim-history 0
    set awareness random-float 1
  ]

  ask n-of num-offenders people [
    set offender? true
    set color red
    set size 8
    set crimes-committed 0
    set motivation random-float 1
  ]
end

;; --------------------------------
;;      GO PROCEDURES
;; -------------------------------

to go
  random-walk
  update-attractiveness
  update-citizens
  commit-crime
  if cur-day = 366 [
    stop
  ]
  draw-plots

end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; UPDATE THE ATTRACTIVENESS OF THE VERTICES IN THE MAP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to update-attractiveness
  ask patches with [corner? = true] [
    ;; the higher the density (max 1) the better for the offender
    set num-people-here count people-here with [active? = true and offender? != true]
    ifelse num-people-here > 0 [
      set density 1 / (num-people-here ^ 2)
    ][ set density 0 ]

    ;; the higher the crime history, the better to the offender
    set crime-hist-vertex crime-hist-vertex * crime-hist-sf

    ;; the time of the day effect is based on the data provided by the police
    ;set time-effect (item cur-hour crime-rates-per-hour) / 113 ;; the vector crime-rates-per-hour presents a sum of 113 robberies
    ;set time-effect time-crime-effect cur-hour


    ;let update-factor crime-hist-balance * crime-hist-vertex + ( (1 - crime-hist-balance) * ( density + time-effect)  / 2   )
    ;set attractiveness attractiveness + attractiveness-sf * ( update-factor - attractiveness )
    ;set attractiveness time-effect * density
    ;; for the offender -> the higher the better
    set attractiveness (1 - luminosity ) * density

  ]

end


;; LUMINOSITY IN THE CITY ACCORDING TO THE TIME OF THE DAY (in ticks)
to-report luminosity
  ;; half light at 6am and 6pm. Pick sun at 12pm, and darkness at 12am.
  ;; report 0.5 + 0.5 * sin ( pi * (x - 36 ) / 72 )
  report 0.5 + 0.5 * sin ( 2.5 * (ticks - 36) )
end


to-report alogistic [ x ]
  let omega 5
  let tau 20
  report ((1 / (1 + e ^ (- omega * (x - tau) ) ) ) - (1 / (1 + e ^ (tau * omega)))) * (1 + e ^ (- omega * tau) )
end

;; SINOIDAL MODEL FOR THE EFFECT OF THE TIME
to-report time-crime-effect [ t ]
  ;; in radians
  ;; report 0.5 - 0.5 * sin ( pi * (t - 2) / 12)
  ;; in degrees ( radians * 180 / pi )
  report 0.5 - 0.5 * sin ( 15 * (t - 2))
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; UPDATE THE AWARENESS AND CRIME HISTORY OF THE CITIZENS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to update-citizens
  ask people [
    ifelse robbed? [
      set victim-history 1
      set robbed? false
      set color blue
    ][ set victim-history victim-history * victim-history-sf ]

    ;; awareness-balance gives different weights for victim-history and attractiveness of the place
    ;set awareness (awareness-balance * victim-history + (1 - awareness-balance) * (1 - [ attractiveness ] of mynode) )
    set awareness awareness + awareness-sf * ( attractiveness - awareness)
  ]

end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ASK OFFENDERS TO MAKE DECISIONS ABOUT COMMITTING THE CRIME
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to commit-crime
  ; ask offenders to evaluate the possibility of commiting a crime
  ask people with [offender? = true and active? = true] [
    if motivation > motivation-threshold [
      if [density] of mynode > 0 [
        set victim min-one-of people-here with [active? = true and offender? != true] [awareness]
        if victim != nobody [
          let rfloat random-float 1
          if rfloat < ((1 - [awareness] of victim) * motivation ) [
            set crimes-committed crimes-committed + 1
            set total-crimes total-crimes + 1
            set crimes-in-vertex crimes-in-vertex + 1
            set crime-hist-vertex 1
            set report-crimes-per-hour replace-item cur-hour report-crimes-per-hour ((item cur-hour report-crimes-per-hour ) + 1)
            ask victim [ set robbed? true ]

            ;type "hour: " type cur-hour type victim type " with awareness " type [awareness] of victim type " was robbed by " type self type " with a motivation of " type motivation type "\n"
            ;type rfloat type "\t" type ((1 - [awareness] of victim) * motivation ) type "\n"
            set motivation random-float 0.25


          ]
        ]
      ]
    ]
    ;; motivation adjustment every day
    ;if cur-hour = 0 [
    set motivation motivation + 0.005 * (random-float motivation-sf)
    if motivation > 1 [ set motivation 1 ]
    ;]

  ]
end



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; WALKING ALGORITHM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to random-walk
  time-update

  ask people [
    ; if it is full hour, change the standby nodes
    set prob-standby people-on-the-streets ;; item cur-hour popular-times

    ifelse offender? != true [
      ifelse random-float 1 > prob-standby [
        set active? false
        set hidden? true
      ][
        set active? true
        set hidden? false
      ]
    ][
      ifelse random-float 1 < prob-standby [
        set active? false
        set hidden? true
      ][
        set active? true
        set hidden? false
      ]
    ]


    if active? = true [
      set mynode one-of [myneighbors] of mynode
      move-to mynode
    ]
  ]
  tick
end


to-report people-on-the-streets
  ;; in radians
  ;; report 0.5 + 0.5 * sin ( pi * (t - 54) / 72)
  ;; in degrees ( radians * 180 / pi )
  report 0.51 + 0.5 * sin ( 2.5 * (ticks - 54))
end

;;;;;;;;;;;;;;;;;helper functions;;;;;;;;;;;;;;;;;;;;;;;;;;


to delete-duplicates
  ask vertices [
    if count vertices-here > 1[
      ask other vertices-here [
        ask myself [
          create-links-with other [link-neighbors] of myself
        ]
        die
      ]
    ]
  ]

end

to delete-not-connected
  ask vertices [set test 0]
  ask one-of vertices [set test 1]
  repeat 500 [
    ask vertices with [test = 1] [
      ask myneighbors [
        set test 1
      ]
    ]
  ]
  ask vertices with [test = 0][die]
end

to time-update
  set cur-min (cur-min + 10)

  if cur-min = 60 [
    set cur-hour (cur-hour + 1)
    set cur-min 0
  ]

  if cur-hour = 24 [
    set cur-day (cur-day + 1)
    set cur-hour 0
  ]

  set week-day (cur-day mod 7)

end

to-report density-average
  report count people with [active? = true]  / count vertices
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; PLOTS ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to draw-plots
  if ticks mod 288 = 0 [
    clear-all-plots
    ;no-display
  ]
  if graphics-view [
    ;; Crimes per hour graphics
    set-current-plot "Crimes per hour"
    create-temporary-plot-pen "report_crimes"
    set-plot-pen-mode 1
    foreach (range 0 24)[
      x -> plotxy x item x report-crimes-per-hour
    ]

    ;; Environmental variables
    set-current-plot "Environmental Variables"
    create-temporary-plot-pen "Luminosity"
    set-plot-pen-color 15
    plot luminosity

    create-temporary-plot-pen "Attractiveness"
    set-plot-pen-color 105
    plot mean [attractiveness] of patches with [corner? = true]

    set-current-plot "Density"
    create-temporary-plot-pen "Density"
    set-plot-pen-color 105
    plot density-average
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; NOT IN USE ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; to move
;  time-update
;  ;; Stage 1. For all agents who do not have a destination yet, they need to
;  ;; pick one and plan a route there
;  ask people [
;    if destination = nobody [
;      ;; This commuted does not have a destination.
;      ;; Find a patch that represents a building centroid and make this the destination
;      set destination-patch one-of patches with [corner? = true]
;      set destination [ closest-vertex ] of destination-patch
;      ;; (but make sure the destination isn't the same as the agent's current position)
;      while [destination = mynode] [
;        set destination-patch one-of patches with [corner? = true]
;        set destination [ closest-vertex ] of destination-patch
;      ]
;      ;; Now calculate the shortest path to the destination
;      path-select
;    ]
;  ]
;
;  ;; Stage 2. Move commuters along the path selected
;  ;; don't move if agent is on standby
;  ask people [
;    ; non active nodes wait for one more tick
;    ifelse active? = false [
;      set time-standby time-standby - 1
;      if time-standby = 0 [
;        set active? true
;        set hidden? false
;      ]
;    ][
;      ;; See if the agents is at their destination
;      ifelse xcor != [xcor] of destination or ycor != [ycor] of destination [
;        ;; They are not at the destination. Move along the path.
;        move-to item step-in-path mypath
;        set step-in-path step-in-path + 1
;      ] [
;        ;; They are at the destination. Get ready for the next model iteration.
;        set last-stop destination
;        set destination nobody
;        set mynode closest-vertex
;        ;; put agent to sleep
;        set active? false
;        set hidden? true
;        set time-standby min-ticks-wait + random (max-ticks-wait - min-ticks-wait)
;
;      ]
;    ]
;  ]
;  tick
;end
;
;
;to path-select ;; Use the A-star algorithm to find the shortest path for a given turtle
;
;  set mypath []      ;; A list to store the vertices
;  set step-in-path 0 ;; Keep track of where we are in the list
;
;  ask vertices [ ;; Reset the relevant vertex variables, ready for a new path
;    set dist 99999  set done 0  set lastnode nobody   set color brown
;  ]
;
;  ask mynode [ set dist 0 ] ;; Set the distance to the current node to 0
;
;  ;; The main loop! This loops over all of the vertices, marking them as
;  ;; 'done' once they have been visitted.
;  while [count vertices with [done = 0] > 0] [
;    ;; Find vertices that have not been visited:
;    ask vertices with [dist < 99999 and done = 0][
;      ask myneighbors [
;        ;; Renew the shorstest distance to this point if it is smaller
;        let dist0 distance myself + [dist] of myself
;        if dist > dist0 [ ;; This distance is shorter
;          set dist dist0
;          set done 0 ;; (so that it will renew the dist of its neighbors)
;          set lastnode myself  ;; save the last node to reach here in the shortest path
;        ]
;      ]
;      set done 1  ;; set done 1 when it has renewed it neighbors
;    ]
;  ]
;  ;; At this point, all of the nodes have been visited, and the vertices that
;  ;; are part of the shortest path have stored the previous node in the path in
;  ;; their 'lastnode' variable. The last thing to do is to put the nodes in
;  ;; shortest path into a list called 'mypath'
;  let x destination
;
;  while [x != mynode] [
;    ;if show_path? [ ask x [set color yellow] ] ;;highlight the shortest path
;    set mypath fput x mypath
;    ;;show mypath
;    set x [lastnode] of x
;  ]
;
;end
@#$#@#$#@
GRAPHICS-WINDOW
214
59
763
414
-1
-1
1.5
1
10
1
1
1
0
1
1
1
-180
180
-115
115
1
1
1
ticks
30.0

BUTTON
1
10
67
43
setup
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

SWITCH
222
17
376
50
show-buildings
show-buildings
1
1
-1000

SLIDER
3
90
175
123
num-people
num-people
50
15000
10000.0
50
1
NIL
HORIZONTAL

PLOT
811
356
1329
476
Density
Time
Variable
0.0
10.0
0.0
1.0
true
true
"" ""
PENS

MONITOR
589
10
646
55
day
cur-day
17
1
11

MONITOR
652
11
709
56
hour
cur-hour
17
1
11

MONITOR
717
11
774
56
min
cur-min
17
1
11

BUTTON
2
49
57
82
NIL
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

BUTTON
63
49
118
82
NIL
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
3
135
175
168
num-offenders
num-offenders
0
100
20.0
1
1
NIL
HORIZONTAL

MONITOR
507
10
578
55
Week Day
week-day
0
1
11

SLIDER
6
230
178
263
crime-hist-sf
crime-hist-sf
0
1
0.0
0.1
1
NIL
HORIZONTAL

SLIDER
6
268
178
301
attractiveness-sf
attractiveness-sf
0
1
0.0
0.1
1
NIL
HORIZONTAL

SLIDER
7
307
179
340
victim-history-sf
victim-history-sf
0
1
0.0
0.1
1
NIL
HORIZONTAL

TEXTBOX
9
198
159
223
Speed Factors
20
14.0
1

PLOT
810
11
1042
207
Crimes per hour
time (h)
# of crimes
0.0
24.0
0.0
100.0
false
false
"" ""
PENS

MONITOR
211
421
300
466
NIL
total-crimes
17
1
11

PLOT
810
223
1329
348
Environmental Variables
time
Variables
0.0
10.0
0.0
1.0
true
true
"" ""
PENS

SLIDER
7
376
182
409
awareness-sf
awareness-sf
0
1
0.5
0.05
1
NIL
HORIZONTAL

SLIDER
7
417
182
450
crime-hist-balance
crime-hist-balance
0
1
0.0
0.05
1
NIL
HORIZONTAL

SLIDER
339
425
511
458
motivation-sf
motivation-sf
0
0.1
0.01
0.0001
1
NIL
HORIZONTAL

MONITOR
624
569
843
614
NIL
count people with [active? = true]
17
1
11

MONITOR
283
532
603
577
NIL
count people with [active? = true] / count vertices
17
1
11

SLIDER
35
474
216
507
motivation-threshold
motivation-threshold
0
1
0.9
0.1
1
NIL
HORIZONTAL

SWITCH
597
441
741
474
graphics-view
graphics-view
0
1
-1000

PLOT
1098
84
1298
234
plot 1
NIL
NIL
0.0
10.0
0.0
0.5
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot alogistic luminosity"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
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
NetLogo 6.0.2
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="4320"/>
    <metric>(list (report-crimes-per-hour) (total-crimes))</metric>
    <steppedValueSet variable="awareness-sf" first="0.5" step="0.1" last="1"/>
    <steppedValueSet variable="motivation-sf" first="0.01" step="0.01" last="0.05"/>
    <steppedValueSet variable="motivation-threshold" first="0.1" step="0.1" last="0.9"/>
    <enumeratedValueSet variable="crime-hist-balance">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-offenders">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="victim-history-sf">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="attractiveness-sf">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="10000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment_1_year" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <exitCondition>cur-day = 366</exitCondition>
    <metric>(list (report-crimes-per-hour) (total-crimes))</metric>
    <enumeratedValueSet variable="awareness-sf">
      <value value="0.1"/>
      <value value="0.5"/>
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivation-sf">
      <value value="0.01"/>
      <value value="0.05"/>
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="motivation-threshold">
      <value value="0.1"/>
      <value value="0.5"/>
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-offenders">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="attractiveness-sf">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-people">
      <value value="10000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="graphics-view">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
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
0
@#$#@#$#@
