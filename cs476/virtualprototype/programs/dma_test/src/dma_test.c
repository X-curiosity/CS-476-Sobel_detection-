#include <stdio.h>
#include <ov7670.h>
#include <swap.h>
#include <vga.h>

#define READ_COMMAND 0<<10//useless but idiomatic
#define WRITE_COMMAND 1<<10

#define CI_DMA 20

#define DMA_REG_BUS_ADDR   (1 << 11)
#define DMA_REG_MEM_ADDR   (2 << 11)
#define DMA_REG_BLOCK_SIZE (3 << 11)
#define DMA_REG_BURST_SIZE (4 << 11)
#define DMA_REG_CTRL       (5 << 11)

#define DMA_WRITE (1 << 10)
#define DMA_READ  (0 << 10)

int main () {
  

  ///////////////////PART 1: TEST Custom Instruction + memory/////////////////////////
  uint32_t addr=0x0;
  uint32_t data=0;


  
  for (int i=0;i<512;i++){
    
    //write value in Ci memory
    asm volatile ("l.nios_rrr r0,%[in1], %[in2] ,20"::[in1]"r"(addr|WRITE_COMMAND),
                                                       [in2]"r"(data));                                                   

    
    //Increment addr and value
    data++;
    addr++;
    
  }  
  
  
  addr=0;
  for (int i=0;i<512;i++){
    uint32_t read_data=0;                                                
    //read value in Ci memory
    asm volatile ("l.nios_rrr %[out1],%[in1],r0,20":[out1]"=r"(read_data):
                                                    [in1]"r"(addr|READ_COMMAND) );
    printf("address %d, read %#08x correctness %d \n",addr,read_data,(addr==read_data));
    addr++;
    
  }

  /////////////////PART 2: TEST TRANSFER FROM BUS TO CI MEMORY /////////////////////////
  printf("\n--- PART 2: BUS -> CI MEMORY ---\n");

  // 1. Prepare source data in SDRAM
  volatile uint32_t *src = (uint32_t*)0x00001000;

  for (int i = 0; i < 64; i++) {
    src[i] = 0xA0000000 + i;
  }

  
  
  //clear CI memory:
  data=0;
  addr=0;
  for (int i=0;i<512;i++){
    
    //write value in Ci memory
    asm volatile ("l.nios_rrr r0,%[in1], %[in2] ,20"::[in1]"r"(addr|WRITE_COMMAND),
                                                       [in2]"r"(data));                                                   

    
    //Increment addr
    addr++;
    
  }  

  // 2. Configure DMA

  // bus start address
  asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
    [a]"r"(DMA_REG_BUS_ADDR | DMA_WRITE),
    [b]"r"(0x00001000));

  // mem start address
  asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
    [a]"r"(DMA_REG_MEM_ADDR | DMA_WRITE),
    [b]"r"(0));

  // block size (words)
  asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
    [a]"r"(DMA_REG_BLOCK_SIZE | DMA_WRITE),
    [b]"r"(64));

  // burst size
  asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
    [a]"r"(DMA_REG_BURST_SIZE | DMA_WRITE),
    [b]"r"(7)); // 8 words per burst

  

  // 3. Start DMA (bit 0 = 1 → TO_CI)
  asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
    [a]"r"(DMA_REG_CTRL | DMA_WRITE),
    [b]"r"(1));
  
  // 4. Poll status
  uint32_t status;
  do {
    asm volatile ("l.nios_rrr %[out],%[in],r0,20"
      : [out]"=r"(status)
      : [in]"r"(DMA_REG_CTRL | DMA_READ));
  } while (status & 0x1);

  // 5. Verify CI memory
  for (int i = 0; i < 64  ; i++) {
    uint32_t val;
    asm volatile ("l.nios_rrr %[out],%[in],r0,20"
      : [out]"=r"(val)
      : [in]"r"(i | READ_COMMAND));

    printf("CI[%d] = %#08x\n", i, val);
  }


  ///////////////PART 3: TEST TRANSFER FROM CI MEM TO BUS /////////////////////////
  printf("\n--- PART 3: CI MEMORY -> BUS ---\n");

  // 1. Fill CI memory
  for (int i = 0; i < 64; i++) {
    asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
      [a]"r"(i | WRITE_COMMAND),
      [b]"r"(200000000 + i));
  }

  // destination in SDRAM
  volatile uint32_t *dst = (uint32_t*)0x00010000;

  // clear destination
  for (int i = 0; i < 64; i++) {
    dst[i] = 0;
    
  }

  // 2. Configure DMA

  // bus start address
  asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
    [a]"r"(DMA_REG_BUS_ADDR | DMA_WRITE),
    [b]"r"(0x00010000));

  // mem start address
  asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
    [a]"r"(DMA_REG_MEM_ADDR | DMA_WRITE),
    [b]"r"(0));

  // block size
  asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
    [a]"r"(DMA_REG_BLOCK_SIZE | DMA_WRITE),
    [b]"r"(64));

  // burst size
  asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
    [a]"r"(DMA_REG_BURST_SIZE | DMA_WRITE),
    [b]"r"(7));

  // 3. Start DMA (bit 1 = 1 → FROM_CI)
  asm volatile ("l.nios_rrr r0,%[a],%[b],20":: 
    [a]"r"(DMA_REG_CTRL | DMA_WRITE),
    [b]"r"(2));

  // 4. Poll status
  do {
    asm volatile ("l.nios_rrr %[out],%[in],r0,20"
      : [out]"=r"(status)
      : [in]"r"(DMA_REG_CTRL | DMA_READ));
  } while (status & 0x1);


  
  // 5. Verify SDRAM
  for (int i = 0; i < 64; i++) {
    printf("MEM[%d] = %#08x\n", i, dst[i]);
    volatile uint32_t tmp = dst[i];
  }

  printf("DONE \n");
  


}
