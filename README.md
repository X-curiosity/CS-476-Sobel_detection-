# PW2 - part2
## Group 25: Oliver Daoud 356765, Xavier Magbi 340062

#### Files changed: 

camera module: cs476/virtualprototype/modules/camera/verilog/camera.v
- changed from fetching/storing 2 pixels in a row to 4, consequently the conversion of 4 pixels simultaneously. We also changed the counters to decrement every 4 pixel for the output

streaming program: cs476/virtualprototype/programs/streaming/src/streaming.c
- commented the #DEFINE directive to load grayscale to the VGA interface

#### Observations

These modifications do not directly affect the output and it is visibly the same as in task2. However we do reduce the number of transfers as the size is smaller, and we get into the grayscale memory a result that is in grayscale format and thus useful to compute the sobel operator. 

#### Final test / How to run VP:

- synthesize and upload toplevel using the synthesis script
- build code in cs476/virtualprototype/programs/dmaTest and upload it to the board via UART
