// key.pressed with an unknown name must warn (once) and return false, not exit.
import "qa"
import "soda"
qa.assert key.pressed("notAKey") == false, "bad name should return false"
qa.assert key.pressed("notAKey") == false, "second call should also return false"
qa.assert key.pressed("mouse ") == false, "bad mouse name should return false"
qa.assert key.pressed("joystick 1 button 99") == false, "bad joystick button"
qa.assert key.pressed("a") == false or key.pressed("a") == true, "good name still works"
print "ALL PASSED"
exit
