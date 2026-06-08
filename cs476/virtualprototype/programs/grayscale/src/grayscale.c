#include <stdio.h>
#include <ov7670.h>
#include <swap.h>
#include <vga.h>

#define __WITH_DMA__

#define READ_COMMAND 0<<10//useless but idiomatic
#define WRITE_COMMAND 1<<10

#define CI_DMA 0x14

#define DMA_REG_BUS_ADDR   (1 << 11)
#define DMA_REG_MEM_ADDR   (2 << 11)
#define DMA_REG_BLOCK_SIZE (3 << 11)
#define DMA_REG_BURST_SIZE (4 << 11)
#define DMA_REG_CTRL       (5 << 11)

#define DMA_WRITE (1 << 10)
#define DMA_READ  (0 << 10)

//function to configure DMA
void configureDMA(uint32_t busAddr,uint32_t memAddr, uint32_t burstSize, uint32_t blockSize) {      
  // bus start address 
  asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
    [a]"r"(DMA_REG_BUS_ADDR | DMA_WRITE),
    [b]"r"(busAddr));

  // mem start address
  asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
    [a]"r"(DMA_REG_MEM_ADDR | DMA_WRITE),
    [b]"r"(memAddr));

  // block size (words)
  asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
    [a]"r"(DMA_REG_BLOCK_SIZE | DMA_WRITE),
    [b]"r"(blockSize));

  // burst size
  asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
    [a]"r"(DMA_REG_BURST_SIZE | DMA_WRITE),
    [b]"r"(burstSize-1)); 
}


int main() {

  const uint32_t writeBit          = 1 << 10;
  const uint32_t busStartAddress   = 1 << 11;
  const uint32_t memoryStartAddress= 2 << 11;
  const uint32_t blockSize         = 3 << 11;
  const uint32_t burstSize         = 4 << 11;
  const uint32_t statusControl     = 5 << 11;

  

  volatile uint8_t  grayscale[640*480];
  volatile uint8_t  sobel[640*480];
  volatile uint32_t result, cycles, stall, idle;
  volatile unsigned int *vga  = (unsigned int *) 0x50000020;
  volatile unsigned int *gpio = (unsigned int *) 0x40000000;
  camParameters camParams;
  vga_clear();

  printf("Initialising camera (this takes up to 3 seconds)!\n");
  camParams = initOv7670(VGA);
  printf("Done!\n");
  printf("NrOfPixels : %d\n", camParams.nrOfPixelsPerLine);
  result = (camParams.nrOfPixelsPerLine <= 320)
           ? camParams.nrOfPixelsPerLine | 0x80000000
           : camParams.nrOfPixelsPerLine;
  vga[0] = swap_u32(result);
  printf("NrOfLines  : %d\n", camParams.nrOfLinesPerImage);
  result = (camParams.nrOfLinesPerImage <= 240)
           ? camParams.nrOfLinesPerImage | 0x80000000
           : camParams.nrOfLinesPerImage;
  vga[1] = swap_u32(result);
  printf("PCLK (kHz) : %d\n", camParams.pixelClockInkHz);
  printf("FPS        : %d\n", camParams.framesPerSecond);

  vga[2] = swap_u32(2);
  vga[3] = swap_u32((uint32_t) &sobel[0]);

  const uint32_t stride = camParams.nrOfPixelsPerLine; /* bytes per line */

  volatile uint16_t line1Addr=0;
  volatile uint16_t line2Addr=160;
  volatile uint16_t line3Addr=320;
  volatile uint16_t line4Addr=480;
  volatile uint32_t busAddr=(uint32_t) &grayscale[0];
  volatile uint32_t sobelAddr=(uint32_t) &sobel[0];
  volatile uint32_t status;

  volatile uint32_t workReg;

  volatile uint32_t lb1,lb2,lb3;

  volatile uint16_t wordCtr,bitCtr;

  while (1) {
    takeSingleImageBlocking((uint32_t) &grayscale[0]);
    asm volatile("l.nios_rrr r0,r0,%[in2],12" :: [in2]"r"(7));

    

    //fetch first 3 lines with DMA 
    configureDMA(busAddr,line1Addr,255,480);

    // Start DMA (bit 0 = 1 => TO_CI)
    asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
        [a]"r"(DMA_REG_CTRL | DMA_WRITE),
        [b]"r"(1));

    //wait until transfer is complete 
    do {
      asm volatile ("l.nios_rrr %[out],%[in],r0,20"
        : [out]"=r"(status)
        : [in]"r"(DMA_REG_CTRL | DMA_READ));
    } while (status & 0x1);

    for (int line=1;line< camParams.nrOfLinesPerImage-3; line++){

      //start dma fetch new line in unsused memory space 
      configureDMA(busAddr+line+2,line1Addr,159,160);
      // Start DMA (bit 0 = 1 => TO_CI)
      asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
          [a]"r"(DMA_REG_CTRL | DMA_WRITE),
          [b]"r"(1));
      

      //fetch 3x rows (first 4 pixels):
      asm volatile("l.nios_rrr %[out1],%[in1],r0,20"
                        : [out1]"=r"(lb1) : [in1]"r"(line1Addr));
      asm volatile("l.nios_rrr %[out1],%[in1],r0,20"
                        : [out1]"=r"(lb1) : [in1]"r"(line2Addr));
      asm volatile("l.nios_rrr %[out1],%[in1],r0,20"
                        : [out1]"=r"(lb1) : [in1]"r"(line3Addr));

      //push to quadCiSR:
      workReg=lb1&0xF|((lb2&0xF)<<8)|((lb3&0xF)<<16);
      asm volatile("l.nios_rrr r0,%[in1],%[in2],14"
                        : : [in1]"r"(0), [in2]"r"(workReg));

      workReg=((lb1&0xF0)>>8)|((lb2&0xF0))|((lb3&0xF0)<<8);
      asm volatile("l.nios_rrr r0,%[in1],%[in2],14"
                        : : [in1]"r"(0), [in2]"r"(workReg));

      workReg=((lb1&0xF00)>>16)|((lb2&0xF00)>>8)|((lb3&0xF00));
      asm volatile("l.nios_rrr r0,%[in1],%[in2],14"
                        : : [in1]"r"(0), [in2]"r"(workReg));
      
      workReg=((lb1&0xF000)>>24)|((lb2&0xF000)>>16)|((lb3&0xF000)>>8);
      asm volatile("l.nios_rrr r0,%[in1],%[in2],14"
                        : : [in1]"r"(0), [in2]"r"(workReg));
      

      wordCtr=1;
      
      
      //fetch 3x rows (second 4 pixels):
      asm volatile("l.nios_rrr %[out1],%[in1],r0,20"
                        : [out1]"=r"(lb1) : [in1]"r"(line1Addr+wordCtr));
      asm volatile("l.nios_rrr %[out1],%[in1],r0,20"
                        : [out1]"=r"(lb1) : [in1]"r"(line2Addr+wordCtr));
      asm volatile("l.nios_rrr %[out1],%[in1],r0,20"
                        : [out1]"=r"(lb1) : [in1]"r"(line3Addr+wordCtr));

      //push to quadCiSR:
      workReg=lb1&0xF|((lb2&0xF)<<8)|((lb3&0xF)<<16);
      asm volatile("l.nios_rrr r0,%[in1],%[in2],14"
                        : : [in1]"r"(0), [in2]"r"(workReg));
      
      bitCtr=1;

      for (int pixel=1; pixel < camParams.nrOfPixelsPerLine-1; pixel+=4) { 
        //push 1 pixel to quadSobel
        if (bitCtr==0){
          workReg=lb1&0xF|((lb2&0xF)<<8)|((lb3&0xF)<<16);
          asm volatile("l.nios_rrr r0,%[in1],%[in2],14"
                        : : [in1]"r"(0), [in2]"r"(workReg));
          bitCtr++;
        }
        
        else if (bitCtr==1){
          workReg=((lb1&0xF0)>>8)|((lb2&0xF0))|((lb3&0xF0)<<8);
          asm volatile("l.nios_rrr r0,%[in1],%[in2],14"
                        : : [in1]"r"(0), [in2]"r"(workReg));
          bitCtr++;
        }

        else if (bitCtr==2){
          workReg=((lb1&0xF00)>>16)|((lb2&0xF00)>>8)|((lb3&0xF00));
          asm volatile("l.nios_rrr r0,%[in1],%[in2],14"
                            : : [in1]"r"(0), [in2]"r"(workReg));
          bitCtr++;
        }

        else if (bitCtr==3){
          workReg=((lb1&0xF000)>>24)|((lb2&0xF000)>>16)|((lb3&0xF000)>>8);
          asm volatile("l.nios_rrr r0,%[in1],%[in2],14"
                            : : [in1]"r"(0), [in2]"r"(workReg));
          bitCtr=0;
          wordCtr++;
          //fetch 3x rows (second 4 pixels):
          asm volatile("l.nios_rrr %[out1],%[in1],r0,20"
                            : [out1]"=r"(lb1) : [in1]"r"(line1Addr+wordCtr));
          asm volatile("l.nios_rrr %[out1],%[in1],r0,20"
                            : [out1]"=r"(lb1) : [in1]"r"(line2Addr+wordCtr));
          asm volatile("l.nios_rrr %[out1],%[in1],r0,20"
                            : [out1]"=r"(lb1) : [in1]"r"(line3Addr+wordCtr));
        }

        //compute 4 sobel using Ci 
        uint32_t mag = 0;
        asm volatile("l.nios_rrr %[out1],%[in1],%[in2],14"
                    : [out1]"=r"(mag) : [in1]"r"(1), [in2]"r"(0));
        

        //put pixel in first row to be unused 
        //write back in memory
        asm volatile ("l.nios_rrr r0,%[in1], %[in2] ,0x14"::[in1]"r"((line1Addr+pixel%4)|WRITE_COMMAND),
                                                          [in2]"r"(0));
      } 
        //look if dma transfer to the Ci mem is done 
        do {
          asm volatile ("l.nios_rrr %[out],%[in],r0,20"
            : [out]"=r"(status)
            : [in]"r"(DMA_REG_CTRL | DMA_READ));
        } while (status & 0x1);
        //dma transfer to the memory spot
        configureDMA(sobelAddr+line*160,line1Addr,159,160);

        // Start DMA (bit 1 = 1 → FROM_CI)
        asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
          [a]"r"(DMA_REG_CTRL | DMA_WRITE),
          [b]"r"(2));
        
        //update pointers  => ring buffer
        status=line1Addr;
        line1Addr=line2Addr;
        line2Addr=line3Addr;
        line3Addr=line4Addr;
        line4Addr=status;
        

        //wait for dma to finish 
        do {
          asm volatile ("l.nios_rrr %[out],%[in],r0,20"
            : [out]"=r"(status)
            : [in]"r"(DMA_REG_CTRL | DMA_READ));
        } while (status & 0x1);
    
    
    }

    asm volatile("l.nios_rrr %[out1],r0,%[in2],12"
                 : [out1]"=r"(cycles) : [in2]"r"(1<<8 | 7<<4));
    asm volatile("l.nios_rrr %[out1],%[in1],%[in2],12"
                 : [out1]"=r"(stall) : [in1]"r"(1), [in2]"r"(1<<9));
    asm volatile("l.nios_rrr %[out1],%[in1],%[in2],12"
                 : [out1]"=r"(idle) : [in1]"r"(2), [in2]"r"(1<<10));
    printf("nrOfCycles: %d %d %d\n", cycles, stall, idle);
  }

  
  

}