#???ù???????
rm(list=ls())
setwd("D:\\GlobalSolarNet\\Optimization")
library(ggplot2)

df <- read.table("Pressure.txt",header = T, check.names = F)

data <- data.frame(
  angle = rep(seq(15, 360, by=18), times=1),
  radius = c(df$P1))

# ????õ?廨ͼ
ggplot(data, aes(x=angle, y=radius, fill=radius)) +
  geom_bar(stat="identity", width=10) +
  coord_polar(theta = "x",start=0) +
  theme_bw() 

data <- data.frame(
  angle = rep(seq(15, 360, by=18), times=1),
  radius = c(df$P2))

# ????õ?廨ͼ
ggplot(data, aes(x=angle, y=radius, fill=radius)) +
  geom_bar(stat="identity", width=10) +
  coord_polar(theta = "x",start=0) +
  theme_bw() 



# ????ʾ??????
data <- data.frame(
  angle = rep(seq(15, 360, by=18), times=2),
  radius = c(df$P2, df$P1),
  group = rep(1:2, each=20)
)

# ????õ?廨ͼ
ggplot(data, aes(x=angle, y=radius, fill=factor(group))) +
  geom_bar(stat="identity", width=10) +
  coord_polar(theta = "x",start=0) +
  theme_bw() +
  scale_fill_manual(values=c("pink", "red"))





library(ggplot2)
#????????
mtcars1=data.frame(
  cars=row.names(mtcars),
  mpg=mtcars$mpg
)
ggplot(mtcars1, aes(x=reorder(cars, mpg), y=mpg, fill=mpg)) +
  geom_bar(width = 1,stat="identity",colour = "black") +
  geom_text(aes(y = mpg-4,label = mpg),color="black",size=2.5) +
  coord_polar(theta = "x",start=0) +
  scale_fill_gradient(low="white",high="#ffd200")+
  ylim(c(0,35))+
  theme_bw()+
  theme(legend.position = 'none',
        axis.text.x=element_text(size = 6))+
  xlab("")+ylab("") 


