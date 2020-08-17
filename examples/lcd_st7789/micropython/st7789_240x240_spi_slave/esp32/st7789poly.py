# ST7789 display with polyline accelerator core
# general puprose drawing: clear screen set color and polyine

from machine import SPI,Pin,freq

@micropython.viper
def color565(r:int, g:int, b:int) -> int:
    """Convert red, green and blue values (0-255) into a 16-bit 565 encoding."""
    return (r & 0xf8) << 8 | (g & 0xfc) << 3 | b >> 3

class st7789poly:
  def __init__(self,width,height,csn,busy,spi):
    self.width=width
    self.height=height
    self.csn=csn # Pin.OZT
    self.busy=busy # Pin.IN
    self.spi=spi # SPI st7789, self.spi.write(bytearray([...]))
    self.load_poly=bytearray([0, 0x1C,0xDD,0x00,0x00]) # loade buffer, follows: XMSB,XLSB,YMSB,YLSB
    self.color_draw=bytearray([0, 0x1C,0xDE,0x00,0x00, 0,0]) # draw buffer, last 2 bytes = color MSB,LSB 
    self.end_poly=bytearray([0x80,0x00,0x00,0x00, 0x00,0x00,0x80,0x00]) # HACK off-screen draw one pixel

  def polyline(self, poly, color:int):
    while self.busy.value():
      continue
    self.csn.off()
    self.spi.write(self.load_poly)
    y=0
    for x in poly:
      if y: # y+80 required with HW rotation
        x+=80
      self.spi.write(bytearray([x>>8,x]))
      y^=1
    self.csn.on()
    self.draw_poly(color)

  @micropython.viper
  def draw_poly(self, color:int):
    c8 = ptr8(addressof(self.color_draw))
    c8[5]=color>>8
    c8[6]=color
    self.csn.off()
    self.spi.write(self.color_draw)
    self.csn.on()

  def cls(self):
    x0 = 0 | 32768 # discontinue
    x1 = 239
    while self.busy.value():
      continue
    self.csn.off()
    self.spi.write(self.load_poly)
    for i in range(240):
      y0 = i+80
      y1 = i+80
      if i==239:
        y1 |= 32768 # last point
      self.spi.write(bytearray([x0>>8,x0,y0>>8,y0,x1>>8,x1,y1>>8,y1]))
    self.csn.on()
    self.draw_poly(color)
