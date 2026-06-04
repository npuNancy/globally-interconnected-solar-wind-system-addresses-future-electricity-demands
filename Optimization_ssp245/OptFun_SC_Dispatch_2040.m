function f = OptFun_SC_Dispatch_2040(ins_cap,gens,loads,CGrid_Index,scale,base_load_ratio)
% OptFun_SC_Dispatch_2040 — 2040年调度模拟与目标函数（大陆互联 S-C）
%
% 输入：
%   ins_cap           - 候选格网装机容量向量（TWp）
%   gens              - 候选格网发电时序矩阵（TWh, 8760h）
%   loads             - 20区域负荷时序矩阵（TW, 8760h）
%   CGrid_Index       - 候选格网区域索引矩阵 [区域编号, 选中状态, 陆海标记]
%   scale             - 决策向量 [选址(0/1) | 储能功率(20) | 储能时长(20) | 输电容量(n_trans)]
%   base_load_ratio   - 基荷比例（来自 optimization_config.m）
%
% 输出：
%   f(1) - 弃电率（curtailment rate）
%   f(2) - 1 - 可再生渗透率（flexible generation ratio）
%   f(3) - 系统总成本（十亿美元）

%% ======================== 1. 计算各区域发电曲线 ========================
CGrid_Index(:,2)=round(scale(1:length(CGrid_Index)));
grid_gens=zeros(20,8760);
for gg_ind=1:20
    index=find((CGrid_Index(:,1)==gg_ind)&(CGrid_Index(:,2)==1));
    selgens=gens(index,:);
    grid_gens(gg_ind,:)=nansum(selgens,1);
end

%% ======================== 2. 扣除基荷发电 ========================
% AR6 SSP2-4.5 情景下，2040年基荷发电占63.9%
grid_load=loads;
for gg_ind=1:20
    tmp=grid_load(gg_ind,:);
    tmp=tmp-sum(tmp)*base_load_ratio/8760;  % 基荷比例由参数传入
    grid_load(gg_ind,:)=tmp;
end

%% ======================== 3. 储能与输电参数 ========================
toStorageLoss=0.95;    % 储能充电效率
fromStorageLoss=0.95;  % 储能放电效率
load Global_Trans trans_connections trans_loss
trans_connections(trans_connections==2)=0;  % 大陆互联：移除跨洲连接

storagePow=scale(length(CGrid_Index)+1:length(CGrid_Index)+20)/1000; %储能功率（TW）
storageCap=storagePow.*scale(length(CGrid_Index)+21:length(CGrid_Index)+40); %储能容量（TWh）

%% ======================== 4. 调度变量初始化 ========================
stored_ele=zeros(8761,20);
stored_ele(1,:)=storageCap*0.5;
curtailed_ele=zeros(8760,20);
flexible_ele=zeros(8760,20);
shifted_ele=zeros(8760,20,20);
consumed_ele=zeros(8760,20);

%% ======================== 5. 构建输电拓扑与路径 ========================
trans_power=zeros(20,20);
trans_power(trans_connections==1)=scale(length(CGrid_Index)+41:end)/1000;
all_paths=[];
all_costs=[];
for gg_ind=1:20
    startNode = gg_ind;
    minNodes = 2;
    maxNodes = 3;   % 大陆互联：最多2跳
    trans_conn=int16(trans_power>0);
    [tmp_paths, tmp_costs] = findAllPathsFromStart(trans_conn, trans_loss,startNode, minNodes, maxNodes);
    [tmp_costs, sortOrder] = sort(tmp_costs);
    tmp_paths = tmp_paths(sortOrder);
    tmp_costs=tmp_costs(tmp_costs<1);
    tmp_paths=tmp_paths(tmp_costs<1);
    all_paths{gg_ind}=tmp_paths;
    all_costs{gg_ind}=tmp_costs;
end
clear tmp_paths tmp_costs

%% ======================== 6. 8760小时调度循环 ========================
for time_ind=1:8760
    trans_power=zeros(20,20);
    trans_power(trans_connections==1)=scale(length(CGrid_Index)+41:end)/1000;
    d_g_s=zeros(20,3);
    d_g_s(:,1)=grid_load(:,time_ind);
    d_g_s(:,2)=grid_gens(:,time_ind);
    d_g_s(:,3)=d_g_s(:,2)-d_g_s(:,1);

    index=d_g_s(:,3)<0;
    consumed_ele(time_ind,index)=d_g_s(index,2);
    consumed_ele(time_ind,~index)=d_g_s(~index,1);

    % 跨区输电调度
    for gg_ind=1:20
        if d_g_s(gg_ind,3)<=0, continue; end
        g_costs=all_costs{gg_ind};
        g_paths=all_paths{gg_ind};
        for ad_grid_ind=1:length(g_paths)
            g_route=g_paths{ad_grid_ind};
            if d_g_s(g_route(end),3)>=0, continue; end
            g_capacities = calculatePathCapacity(g_route,trans_power);
            if g_capacities<=0, continue; end
            t_amount=min(min(abs(d_g_s(g_route(end),3))/(1-g_costs(ad_grid_ind)),g_capacities),d_g_s(gg_ind,3));
            shifted_ele(time_ind,gg_ind,g_route(end))=shifted_ele(time_ind,gg_ind,g_route(end))+t_amount;
            d_g_s(gg_ind,3)=d_g_s(gg_ind,3)-t_amount;
            d_g_s(g_route(end),3)=d_g_s(g_route(end),3)+t_amount*(1-g_costs(ad_grid_ind));
            for j = 1:(length(g_route) - 1)
                trans_power(g_route(j),g_route(j + 1))=trans_power(g_route(j),g_route(j + 1))-t_amount;
            end
        end
    end

    % 储能充放电调度
    for gg_ind=1:20
        if d_g_s(gg_ind,3)>=0  % 富余 → 充电
            t_amount=min(min(d_g_s(gg_ind,3),storagePow(gg_ind)),(storageCap(gg_ind)-stored_ele(time_ind,gg_ind))/toStorageLoss);
            stored_ele(time_ind+1,gg_ind)=stored_ele(time_ind,gg_ind)+t_amount*toStorageLoss;
            curtailed_ele(time_ind,gg_ind)=d_g_s(gg_ind,3)-t_amount;
            d_g_s(gg_ind,3)=0;
        else  % 缺电 → 放电
            t_amount=min(min(storagePow(gg_ind)/fromStorageLoss,abs(d_g_s(gg_ind,3))),stored_ele(time_ind,gg_ind));
            stored_ele(time_ind+1,gg_ind)=max(stored_ele(time_ind,gg_ind)-t_amount,0);
            flexible_ele(time_ind,gg_ind)=abs(d_g_s(gg_ind,3)+t_amount);
            d_g_s(gg_ind,3)=0;
        end
    end
end

%% ======================== 7. 计算系统总成本 ========================
load NonlConData2040.mat nonlsol
obj_cost=0;
index=find((CGrid_Index(:,3)==1)&(CGrid_Index(:,2)==1));  % 海上风电
obj_cost=obj_cost+3461*sum(ins_cap(index(index>nonlsol)));

index=find((CGrid_Index(:,1)>8)&(CGrid_Index(:,1)<14)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));  % 亚洲
obj_cost=obj_cost+927.6*sum(ins_cap(index(index<=nonlsol)));
obj_cost=obj_cost+1313*sum(ins_cap(index(index>nonlsol)));

index=find((CGrid_Index(:,1)==1)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));  % 北美
obj_cost=obj_cost+1012.6*sum(ins_cap(index(index<=nonlsol)));
obj_cost=obj_cost+1284.8*sum(ins_cap(index(index>nonlsol)));

index=find((CGrid_Index(:,1)>4)&(CGrid_Index(:,1)<9)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));  % 欧洲
obj_cost=obj_cost+1075.9*sum(ins_cap(index(index<=nonlsol)));
obj_cost=obj_cost+1650.4*sum(ins_cap(index(index>nonlsol)));

index=find((CGrid_Index(:,1)>1)&(CGrid_Index(:,1)<5)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));  % 拉丁美洲
obj_cost=obj_cost+861.4*sum(ins_cap(index(index<=nonlsol)));
obj_cost=obj_cost+1499.4*sum(ins_cap(index(index>nonlsol)));

index=find((CGrid_Index(:,1)>15)&(CGrid_Index(:,1)<21)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));  % 非洲
obj_cost=obj_cost+1256.6*sum(ins_cap(index(index<=nonlsol)));
obj_cost=obj_cost+1684.7*sum(ins_cap(index(index>nonlsol)));

index=find((CGrid_Index(:,1)>13)&(CGrid_Index(:,1)<16)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));  % 大洋洲
obj_cost=obj_cost+922.5*sum(ins_cap(index(index<=nonlsol)));
obj_cost=obj_cost+1360.7*sum(ins_cap(index(index>nonlsol)));

trans_power=zeros(20,20);
trans_power(trans_connections==1)=scale(length(CGrid_Index)+41:end)/1000;
obj_cost=obj_cost+98*sum(trans_power(:));   % 输电
obj_cost=obj_cost+350*sum(storageCap(:));    % 储能

%% ======================== 8. 返回三目标函数值 ========================
f(1)=sum(curtailed_ele(:))./sum(grid_gens(:));   % 弃电率
f(2)=sum(flexible_ele(:))./sum(loads(:));         % 1 - 可再生渗透率
f(3)=obj_cost;                                     % 总成本（十亿美元）
end
