package main

const (
	fbWidth            = 80
	fbHeight           = 25
	fbPhysAddr uintptr = 0xb8000
)

func main() {
	return
}

// delay implements a simple loop-based delay. The outer loop value is selected
// so that a reasonable delay is generated when running on virtualbox.
func delay(v int) {
	for i := 0; i < 684000; i++ {
		for j := 0; j < v; j++ {
		}
	}
}
