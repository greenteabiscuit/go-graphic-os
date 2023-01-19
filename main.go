package main

const (
	fbWidth            = 80
	fbHeight           = 25
	fbPhysAddr uintptr = 0xb8000
)

func main() {

}

// transition implements a slide transition using the current contents of the
// supplied framebuffer.
func transition(fb []uint16) {
	delay(5000)

	for i := 0; i < fbWidth; i++ {
		for y, off := 0, 0; y < fbHeight; y, off = y+1, off+fbWidth {
			// Even rows should slide one character to the left and
			// odd rows should slide one character to the right
			if y%2 == 0 {
				copy(fb[off:off+fbWidth], fb[off+1:off+fbWidth])
				fb[off+fbWidth-1] = ' '
			} else {
				copy(fb[off+1:off+fbWidth], fb[off:off+fbWidth-1])
				fb[off] = ' '
			}
		}
		delay(50)
	}
}

// delay implements a simple loop-based delay. The outer loop value is selected
// so that a reasonable delay is generated when running on virtualbox.
func delay(v int) {
	for i := 0; i < 684000; i++ {
		for j := 0; j < v; j++ {
		}
	}
}
