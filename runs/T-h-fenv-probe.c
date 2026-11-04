/* T-h follow-on: does THIS platform apply directed rounding? */
#include <fenv.h>
#include <stdio.h>
int main(void) {
  volatile double x = 0.1, y = -3.0;
  printf("initial fegetround=%d (TN=%d DN=%d UP=%d)\n", fegetround(), FE_TONEAREST, FE_DOWNWARD, FE_UPWARD);
  printf("no-mode      0.1+(-3) = %a\n", (double)(x + y));
  int rc = fesetround(FE_DOWNWARD);
  volatile double d = x + y;
  printf("fesetround(DOWN) rc=%d fegetround=%d -> %a\n", rc, fegetround(), d);
  fesetround(FE_UPWARD);
  volatile double u = x + y;
  printf("fesetround(UP)   rc=%d fegetround=%d -> %a\n", fegetround(), fegetround(), u);
  fesetround(FE_TONEAREST);
  return 0;
}
