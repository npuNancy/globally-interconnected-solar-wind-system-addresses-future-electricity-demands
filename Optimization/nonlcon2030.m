function [c,ceq] = nonlcon2030(x)
load NonlConData2030.mat nonlcon_sel nonlcon_ins nonlsol nonlwin
load Global_Init_State cur_solar cur_wind
cur_solar=cur_solar/1000/1000;
cur_wind=cur_wind/1000/1000;
tmp_a=x(1:nonlsol);
tmp_b=nonlcon_ins(1:nonlsol);
tmp_c=tmp_a(:).*tmp_b(:);
tmp_d=nonlcon_sel(1:nonlsol);
tmp_solar=[];
for i=1:20
    index=find(tmp_d==i);
    tmp_solar=[tmp_solar;sum(tmp_c(index))];
end
tmp_e=tmp_solar<cur_solar;
c(1)=sum(tmp_e);

tmp_a2=x(nonlsol+1:nonlsol+nonlwin);
tmp_b2=nonlcon_ins(nonlsol+1:nonlsol+nonlwin);
tmp_c2=tmp_a2(:).*tmp_b2(:);
tmp_d2=nonlcon_sel(nonlsol+1:nonlsol+nonlwin);
tmp_wind=[];
for i=1:20
    index=find(tmp_d2==i);
    tmp_wind=[tmp_wind;sum(tmp_c2(index))];
end
tmp_e2=tmp_wind<cur_wind;
c(2)=sum(tmp_e2);
ceq=[];
end