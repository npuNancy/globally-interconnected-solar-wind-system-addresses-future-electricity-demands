function f = OptFun_SC_Dispatch_2050(ins_cap,gens,loads,CGrid_Index,scale)
% OptFun_SC_Dispatch_2050 — 2050年调度模拟与目标函数（大陆互联 S-C）
%
% 输入：
%   ins_cap     - 候选格网装机容量向量（TWp）
%   gens        - 候选格网发电时序矩阵（TWh, 8760h）
%   loads       - 20区域负荷时序矩阵（TW, 8760h）
%   CGrid_Index - 候选格网区域索引矩阵 [区域编号, 选中状态, 陆海标记]
%   scale       - 决策向量 [选址(0/1) | 储能功率(20) | 储能时长(20) | 输电容量(n_trans)]
%
% 输出：
%   f(1) - 弃电率（curtailment rate）
%   f(2) - 1 - 可再生渗透率（flexible generation ratio）
%   f(3) - 系统总成本（十亿美元）

%% ======================== 1. 计算各区域发电曲线 ========================
% 根据选址结果（scale前N_grid个0/1变量），汇总每个区域的总发电功率
CGrid_Index(:,2)=round(scale(1:length(CGrid_Index)));
grid_gens=zeros(20,8760);
for gg_ind=1:20
    index=find((CGrid_Index(:,1)==gg_ind)&(CGrid_Index(:,2)==1));
    selgens=gens(index,:);
    grid_gens(gg_ind,:)=nansum(selgens,1);
end

%% ======================== 2. 扣除基荷发电（非可再生调度电源） ========================
% AR6 SSP5-6.0 情景下，2050年基荷发电占64.2%
% 从负荷中减去基荷，剩余部分由可再生能源满足
grid_load=loads;
for gg_ind=1:20
    tmp=grid_load(gg_ind,:);
    tmp=tmp-sum(tmp)*0.642/8760;  % 基荷占比64.2%，均匀分配至每小时
    grid_load(gg_ind,:)=tmp;
end

%% ======================== 3. 储能与输电参数 ========================
toStorageLoss=0.95;   % 储能充电效率
fromStorageLoss=0.95;  % 储能放电效率
load Global_Trans trans_connections trans_loss
% trans_connections: 区域间连接矩阵（1=大陆内连接，2=跨洲连接）
% trans_loss: 输电损耗率矩阵
trans_connections(trans_connections==2)=0;  % 大陆互联模式：移除跨洲连接

% 从决策向量提取储能参数
storagePow=scale(length(CGrid_Index)+1:length(CGrid_Index)+20)/1000; %储能功率（TW）
storageCap=storagePow.*scale(length(CGrid_Index)+21:length(CGrid_Index)+40); %储能容量（TWh = 功率×时长）

%% ======================== 4. 调度变量初始化 ========================
stored_ele=zeros(8761,20);    % 储能系统各小时存储电量（TWh），初始为容量50%
stored_ele(1,:)=storageCap*0.5;
curtailed_ele=zeros(8760,20); % 各小时弃电量（TWh）
flexible_ele=zeros(8760,20);  % 各小时灵活电源需求（TWh）
shifted_ele=zeros(8760,20,20);% 区域间转移电量（TWh）
consumed_ele=zeros(8760,20);  % 直接消纳电量（TWh）

%% ======================== 5. 构建输电拓扑与路径 ========================
% 恢复输电容量矩阵
trans_power=zeros(20,20);
trans_power(trans_connections==1)=scale(length(CGrid_Index)+41:end)/1000; %输电容量（TW）
all_paths=[];
all_costs=[];
% 对每个区域，DFS搜索所有可行输电路径（大陆互联：最多2跳，maxNodes=3）
for gg_ind=1:20
    startNode = gg_ind;
    minNodes = 2;   % 路径最少2个节点（1跳）
    maxNodes = 3;   % 路径最多3个节点（2跳，大陆内中继）
    trans_conn=int16(trans_power>0);
    [tmp_paths, tmp_costs] = findAllPathsFromStart(trans_conn, trans_loss,startNode, minNodes, maxNodes);
    % 按损耗率升序排列路径
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
    % 恢复输电容量（每小时重置）
    trans_power=zeros(20,20);
    trans_power(trans_connections==1)=scale(length(CGrid_Index)+41:end)/1000;
    % 计算各区域供需差：d_g_s(:,3) < 0 表示缺电，> 0 表示富余
    d_g_s=zeros(20,3);
    d_g_s(:,1)=grid_load(:,time_ind);  % 需求
    d_g_s(:,2)=grid_gens(:,time_ind);  % 发电
    d_g_s(:,3)=d_g_s(:,2)-d_g_s(:,1);  % 差值：<0 缺电；>0 富余

    % 计算直接消纳量
    index=d_g_s(:,3)<0;
    consumed_ele(time_ind,index)=d_g_s(index,2);     % 缺电区域：消纳=发电量
    consumed_ele(time_ind,~index)=d_g_s(~index,1);   % 富余区域：消纳=负荷量

    % --- 跨区输电调度 ---
    % 优先将富余区域的电力输送到缺电区域（按损耗率从低到高）
    for gg_ind=1:20
        if d_g_s(gg_ind,3)<=0
            continue  % 当前区域无富余，跳过
        end
        g_costs=all_costs{gg_ind};
        g_paths=all_paths{gg_ind};
        for ad_grid_ind=1:length(g_paths)
            g_route=g_paths{ad_grid_ind};
            if d_g_s(g_route(end),3)>=0
                continue  % 目标区域不缺电，跳过
            end
            g_capacities = calculatePathCapacity(g_route,trans_power);
            if g_capacities<=0
                continue  % 路径无可用容量
            end
            % 计算实际传输量：取 受端缺电/(1-损耗)、路径容量、送端富余 三者最小值
            t_amount=min(min(abs(d_g_s(g_route(end),3))/(1-g_costs(ad_grid_ind)),g_capacities),d_g_s(gg_ind,3));
            shifted_ele(time_ind,gg_ind,g_route(end))=shifted_ele(time_ind,gg_ind,g_route(end))+t_amount;
            % 更新供需状态
            d_g_s(gg_ind,3)=d_g_s(gg_ind,3)-t_amount;  % 送端剩余富余减少
            d_g_s(g_route(end),3)=d_g_s(g_route(end),3)+t_amount*(1-g_costs(ad_grid_ind));  % 受端缺电减少（含损耗）
            % 更新路径上各段输电容量
            for j = 1:(length(g_route) - 1)
                trans_power(g_route(j),g_route(j + 1))=trans_power(g_route(j),g_route(j + 1))-t_amount;
            end
        end
    end

    % --- 储能充放电调度 ---
    for gg_ind=1:20
        if d_g_s(gg_ind,3)>=0  % 富余 → 充电
            % 充电量受限于：富余量、最大充电功率、剩余储能容量
            t_amount=min(min(d_g_s(gg_ind,3),storagePow(gg_ind)),(storageCap(gg_ind)-stored_ele(time_ind,gg_ind))/toStorageLoss);
            stored_ele(time_ind+1,gg_ind)=stored_ele(time_ind,gg_ind)+t_amount*toStorageLoss;
            curtailed_ele(time_ind,gg_ind)=d_g_s(gg_ind,3)-t_amount;  % 弃电 = 富余 - 实际充电
            d_g_s(gg_ind,3)=0;
        else  % 缺电 → 放电
            % 放电量受限于：缺电量、最大放电功率、当前储能容量
            t_amount=min(min(storagePow(gg_ind)/fromStorageLoss,abs(d_g_s(gg_ind,3))),stored_ele(time_ind,gg_ind));
            stored_ele(time_ind+1,gg_ind)=max(stored_ele(time_ind,gg_ind)-t_amount,0);
            flexible_ele(time_ind,gg_ind)=abs(d_g_s(gg_ind,3)+t_amount);  % 灵活电源需求 = 缺电 - 放电
            d_g_s(gg_ind,3)=0;
        end
    end
end

%% ======================== 7. 计算系统总成本 ========================
load NonlConData.mat nonlsol
obj_cost=0;
% 海上风电：全球统一成本 3461 $/kW → 3461 十亿美元/TW
index=find((CGrid_Index(:,3)==1)&(CGrid_Index(:,2)==1));
obj_cost=obj_cost+3461*sum(ins_cap(index(index>nonlsol)));

% 陆上风电/光伏：各区域差异化成本（低于 nonlsol 阈值的为光伏，高于的为风电）
% 亚洲（区域9-13）
index=find((CGrid_Index(:,1)>8)&(CGrid_Index(:,1)<14)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));
obj_cost=obj_cost+927.6*sum(ins_cap(index(index<=nonlsol)));   % 光伏
obj_cost=obj_cost+1313*sum(ins_cap(index(index>nonlsol)));     % 陆上风电

% 北美（区域1）
index=find((CGrid_Index(:,1)==1)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));
obj_cost=obj_cost+1012.6*sum(ins_cap(index(index<=nonlsol)));
obj_cost=obj_cost+1284.8*sum(ins_cap(index(index>nonlsol)));

% 欧洲（区域5-8）
index=find((CGrid_Index(:,1)>4)&(CGrid_Index(:,1)<9)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));
obj_cost=obj_cost+1075.9*sum(ins_cap(index(index<=nonlsol)));
obj_cost=obj_cost+1650.4*sum(ins_cap(index(index>nonlsol)));

% 拉丁美洲（区域2-4）
index=find((CGrid_Index(:,1)>1)&(CGrid_Index(:,1)<5)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));
obj_cost=obj_cost+861.4*sum(ins_cap(index(index<=nonlsol)));
obj_cost=obj_cost+1499.4*sum(ins_cap(index(index>nonlsol)));

% 非洲（区域16-20）
index=find((CGrid_Index(:,1)>15)&(CGrid_Index(:,1)<21)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));
obj_cost=obj_cost+1256.6*sum(ins_cap(index(index<=nonlsol)));
obj_cost=obj_cost+1684.7*sum(ins_cap(index(index>nonlsol)));

% 大洋洲（区域14-15）
index=find((CGrid_Index(:,1)>13)&(CGrid_Index(:,1)<16)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));
obj_cost=obj_cost+922.5*sum(ins_cap(index(index<=nonlsol)));
obj_cost=obj_cost+1360.7*sum(ins_cap(index(index>nonlsol)));

% 输电成本：98 十亿美元/TW
trans_power=zeros(20,20);
trans_power(trans_connections==1)=scale(length(CGrid_Index)+41:end)/1000;
obj_cost=obj_cost+98*sum(trans_power(:));
% 储能成本：350 十亿美元/TWh
obj_cost=obj_cost+350*sum(storageCap(:));

%% ======================== 8. 返回三目标函数值 ========================
f(1)=sum(curtailed_ele(:))./sum(grid_gens(:));   % 弃电率
f(2)=sum(flexible_ele(:))./sum(loads(:));         % 1 - 可再生渗透率
f(3)=obj_cost;                                     % 总成本（十亿美元）
end
