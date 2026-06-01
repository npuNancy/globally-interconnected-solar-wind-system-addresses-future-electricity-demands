function [c,ceq] = nonlcon2030(x)
% nonlcon2030 — 2030年非线性约束函数
%
% 约束逻辑：确保每个区域选中的光伏/风电装机容量 ≥ 当前已安装容量。
%
% 输出：
%   c(1) - 光伏不满足约束的区域数量（≤0 表示全部满足）
%   c(2) - 风电不满足约束的区域数量（≤0 表示全部满足）
%   ceq  - 等式约束（空）

load NonlConData2030.mat nonlcon_sel nonlcon_ins nonlsol nonlwin
load Global_Init_State cur_solar cur_wind
cur_solar=cur_solar/1000/1000;  % MWp → TWp
cur_wind=cur_wind/1000/1000;

% --- 光伏约束 ---
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

% --- 风电约束 ---
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
