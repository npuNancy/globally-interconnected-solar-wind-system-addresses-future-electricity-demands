function [c,ceq] = nonlcon2050(x)
% nonlcon2050 — 2050年非线性约束函数
%
% 约束逻辑：确保每个区域选中的光伏/风电装机容量 ≥ 当前已安装容量。
% 这是为了保证优化方案在现实中可行——不能拆除已有的电站。
%
% 输入：
%   x - 决策向量（与 gamultiobj 变量一致）
%
% 输出：
%   c(1) - 光伏不满足约束的区域数量（≤0 表示全部满足）
%   c(2) - 风电不满足约束的区域数量（≤0 表示全部满足）
%   ceq  - 等式约束（空，无等式约束）

% 加载候选格网数据和当前装机容量
load NonlConData.mat nonlcon_sel nonlcon_ins nonlsol nonlwin
load Global_Init_State cur_solar cur_wind
cur_solar=cur_solar/1000/1000;  % MWp → TWp
cur_wind=cur_wind/1000/1000;

% --- 光伏约束 ---
% 计算每个区域选中的光伏装机容量
tmp_a=x(1:nonlsol);                 % 光伏选址决策变量（0/1）
tmp_b=nonlcon_ins(1:nonlsol);       % 对应格网的装机容量（TWp）
tmp_c=tmp_a(:).*tmp_b(:);           % 各格网选中的容量
tmp_d=nonlcon_sel(1:nonlsol);       % 各格网所属区域编号
tmp_solar=[];
for i=1:20
    index=find(tmp_d==i);           % 第 i 个区域的所有光伏格网
    tmp_solar=[tmp_solar;sum(tmp_c(index))];  % 汇总该区域选中容量
end
tmp_e=tmp_solar<cur_solar;          % 哪些区域不满足最低装机要求
c(1)=sum(tmp_e);                    % 不满足的区域数

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
