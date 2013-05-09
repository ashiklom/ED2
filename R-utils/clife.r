#------------------------------------------------------------------------------------------#
#   Function that creates a purple to green colour scheme.                                 #
#------------------------------------------------------------------------------------------#
clife <<- function(n){
   rrr       = c(  32,  96,  96, 212, 160,  32,   0)
   ggg       = c(   0,   0, 128, 212, 255, 192,  48)
   bbb       = c(  64, 255, 255,  96,   0,   0,   0)
   nodes     = mapply(FUN=rgb,red=rrr,green=ggg,blue=bbb,MoreArgs=list(maxColorValue=255))

#   nodes     = c("#3F1368","purple2","slateblue","lightslateblue","#C0ACCF"
#                ,"darkolivegreen1","olivedrab3","chartreuse2","forestgreen","#004000")
   nodes     = data.frame(t(col2rgb(nodes)))
   pivot     = round(seq(from=1,to=n,length.out=nrow(nodes)),digits=0)
   rgb.out   = data.frame(t(mapply(FUN=spline,y=nodes,MoreArgs=list(x=pivot,n=n))))$y
   rgb.out   = lapply(X=rgb.out,FUN=as.integer)
   rgb.out   = lapply(X=rgb.out,FUN=pmax,  0)
   rgb.out   = lapply(X=rgb.out,FUN=pmin,255)
   rgb.out   = rgb(r=rgb.out$red,g=rgb.out$green,b=rgb.out$blue,maxColorValue=255)
   return(rgb.out)
}#end function clife
#------------------------------------------------------------------------------------------#




#------------------------------------------------------------------------------------------#
#   Function that creates a nice colour scheme.                                            #
#------------------------------------------------------------------------------------------#
iclife <<- function(n){
   rgb.out   = rev(clife(n=n))
   return(rgb.out)
}#end function iclife
#------------------------------------------------------------------------------------------#
