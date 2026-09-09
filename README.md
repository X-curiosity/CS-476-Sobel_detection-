# Sobel Edge Detection Accelerator

Hardware-accelerated Sobel edge detection and frame differencing for the EPFL CS-476 Embedded System Design virtual prototype.

**Authors:** Oliver Daoud (356765) and Xavier Magbi (340062)  
**Course:** CS-476 Embedded System Design, EPFL  
**Report:** [report_CS-476.pdf](report_CS-476.pdf)

## Overview

This project accelerates a camera-based image-processing pipeline by moving the compute-intensive Sobel operation from the OR1420 CPU to custom hardware. The pipeline converts RGB565 camera pixels to grayscale, computes Sobel edge magnitudes, and compares consecutive Sobel frames to highlight motion.

For each output pixel, the Sobel operator applies horizontal and vertical 3 × 3 kernels and uses the approximation `G = |Gx| + |Gy|` for edge intensity.

## Architecture

The design was developed incrementally:

1. **Software reference implementation** — CPU-only Sobel and motion detection established a correct baseline.
2. **Custom Sobel instruction** — `sobelCi` moved the Sobel arithmetic into dedicated hardware.
3. **DMA-backed CI memory** — the DMA controller transfers image lines directly between main memory and custom-instruction memory, reducing CPU-managed data movement.
4. **Ring buffer** — four line-sized memory regions retain the three lines required by the Sobel neighborhood while DMA prefetches the next line and completed output lines are transferred back in one operation.
5. **Four-pixel sliding window** — `quadSobelCi` maintains a 3 × 6 window, evaluates four overlapping 3 × 3 Sobel neighborhoods in parallel, and packs four 8-bit outputs into one 32-bit word.
6. **Frame differencing** — consecutive Sobel frames are compared in software to detect changes; a magnitude mask suppresses weak edge responses before comparison.

When the window advances, two columns are retained and four new columns are loaded. This avoids rebuilding the full 3 × 6 window and reduces memory traffic and custom-instruction invocations.

## Performance

| Implementation stage | Approximate execution time |
| --- | ---: |
| CPU-only Sobel | 330 million cycles per frame |
| Single Sobel custom instruction | 270 million cycles per frame |
| DMA + line ring buffer + sliding window | 71 million cycles per frame |
| Reduced unnecessary `volatile` accesses | 29 million cycles per frame |

At a 70 MHz clock, the final measured implementation reaches approximately **2.6 frames/s**.

## Repository layout

- `cs476/virtualprototype/modules/sobelCi/verilog/sobelCi.v` — single-pixel Sobel custom instruction.
- `cs476/virtualprototype/modules/quadSobelCi/verilog/quadSobelCi.v` — four-pixel sliding-window Sobel accelerator.
- `cs476/virtualprototype/modules/ramDmaCi/verilog/ramDmaCi.v` — custom-instruction memory interface.
- `cs476/virtualprototype/modules/DMA/verilog/DMA.v` — DMA controller.
- `cs476/virtualprototype/modules/grayscaleCi/verilog/` — RGB565-to-grayscale conversion hardware.
- `cs476/virtualprototype/modules/camera/verilog/camera.v` — camera-side grayscale streaming support.
- `cs476/virtualprototype/programs/streaming/src/streaming.c` — continuous camera capture and VGA setup.
- `cs476/virtualprototype/programs/ramDma/src/ramDma.c` and `programs/dma_test/` — CI-memory and DMA validation programs.
- `cs476/virtualprototype/systems/singleCore/` — OR1420 top level and FPGA synthesis files.

## Build and run

### 1. Build and upload the hardware

The hardware build uses the OSS CAD Suite (Yosys, nextpnr, and ecppack). From the virtual-prototype directory:

```sh
cd systems/singleCore/sandbox
../scripts/synthesizeOr1420.sh
```

The script synthesizes the OR1420 top level, places and routes it, generates the bitstream, and uploads it to the GECKO5 board. To store the bitstream in flash:

```sh
openFPGALoader -f or1420SingleCore.bit
```

### 2. Build a software program

Each program uses the provided Makefile flow. For example, to build the DMA validation program:

```sh
cd programs/dma_test
make clean mem1420
```

The build produces a `.cmem` image under `build-release-or1420/`. Upload the generated `.cmem` file to the board over UART using a terminal program. The OR1420 has no hardware divider, so programs must be compiled with `-msoft-div`.

## Further work

The report identifies two opportunities for additional optimization: use both custom-instruction inputs to load two new pixel columns per call, and move sliding-window management into CI memory so DMA can avoid intermediate transfers.
