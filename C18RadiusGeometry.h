#ifndef C18_RADIUS_GEOMETRY_H
#define C18_RADIUS_GEOMETRY_H
#include <math.h>
static inline double C18RadiusPercent(double value) {
    if (!isfinite(value)) return 0;
    return fmax(0,fmin(100,value));
}
/* Grid class 0 is the shipped 1x1 circular control. A 2x2 square is NOT
   identified by its aspect ratio: it remains eligible for customization. */
static inline int C18RadiusSingle(long size,long columns,long rows,int expanded) {
    if (expanded) return 0;
    if (columns>0 && rows>0) return columns==1 && rows==1;
    return size==0;
}
static inline double C18RadiusInterpolate(double native,double width,double height,double percent) {
    double p=C18RadiusPercent(percent);
    if (!p || !isfinite(native) || !isfinite(width) || !isfinite(height) || width<=0 || height<=0) return native;
    double limit=fmin(width,height)*0.5;
    double start=fmax(0,fmin(native,limit));
    return start+(limit-start)*(p/100.0);
}
#endif
