function [f,con,flex,curtail,storage,shifted] = Fun_SG_Dispatch_2050(ins_cap,gens,loads,CGrid_Index,scale)
% caculate regional generation curves
CGrid_Index(:,2)=round(scale(1:length(CGrid_Index)));
grid_gens=zeros(20,8760);
for gg_ind=1:20
    index=find((CGrid_Index(:,1)==gg_ind)&(CGrid_Index(:,2)==1));
    selgens=gens(index,:);
    grid_gens(gg_ind,:)=nansum(selgens,1);
end
% baseload generation 9% in IEA's NZE
grid_load=loads;
for gg_ind=1:20
    tmp=grid_load(gg_ind,:);
    tmp=tmp-sum(tmp)*0.09/8760;
    grid_load(gg_ind,:)=tmp;
end
toStorageLoss=0.95;%efficiency to store energy
fromStorageLoss=0.95;%efficiecy to use stored energy
load Global_Trans trans_connections trans_loss
%trans_connections (Interconnections.xlsx AdjacencyMatrix)
trans_connections(trans_connections>0)=1;
%trans_loss efficiency of transferring energy (Interconnections.xlsx CostMatrix_Per)
storagePow=scale(length(CGrid_Index)+1:length(CGrid_Index)+20)/1000; %storage power TW
storageCap=storagePow.*scale(length(CGrid_Index)+21:length(CGrid_Index)+40); %storage capacity

% variables for dispatching
stored_ele=zeros(8761,20);%record the stored electricity in the storage system
stored_ele(1,:)=storageCap*0.5;
curtailed_ele=zeros(8760,20);%record the curtailed eletricity at each hour
flexible_ele=zeros(8760,20);%record the required flexible eletricity at each hour
shifted_ele=zeros(8760,20,20);%record the load transfer between adjcent grids
consumed_ele=zeros(8760,20);%record the electricity consumed directly

%Recover transmission capacity
trans_power=zeros(20,20);
trans_power(trans_connections==1)=scale(length(CGrid_Index)+41:end)/1000; %transmission power TW
all_paths=[];
all_costs=[];
for gg_ind=1:20
    startNode = gg_ind;  % start node
    minNodes = 2;   % min nodes
    maxNodes = 6;   % max nodes
    trans_conn=int16(trans_power>0);
    [tmp_paths, tmp_costs] = findAllPathsFromStart(trans_conn, trans_loss,startNode, minNodes, maxNodes);
    % for i = 1:length(g_paths)
    %     disp(['Path ', num2str(i), ': ', num2str(g_paths{i}), ' Cost: ', num2str(g_costs(i))]);
    % end
    % sorting
    [tmp_costs, sortOrder] = sort(tmp_costs);
    tmp_paths = tmp_paths(sortOrder);
    tmp_costs=tmp_costs(tmp_costs<1);
    tmp_paths=tmp_paths(tmp_costs<1);
    all_paths{gg_ind}=tmp_paths;
    all_costs{gg_ind}=tmp_costs;
end
clear tmp_paths tmp_costs

% time_ind=time_ind+1;
for time_ind=1:8760
    %time_ind
    %Recover transmission capacity
    trans_power=zeros(20,20);
    trans_power(trans_connections==1)=scale(length(CGrid_Index)+41:end)/1000; %transmission power TW
    d_g_s=zeros(20,3);
    d_g_s(:,1)=grid_load(:,time_ind);%demand
    d_g_s(:,2)=grid_gens(:,time_ind);%generation
    d_g_s(:,3)=d_g_s(:,2)-d_g_s(:,1);%<0 shortage; >0 surplus
    %if generation < demand, firstly brorrow from the grid with
    %surplus, then use electricity in the storage, then use flexible generation
    %if gengeration > demand, first transfer to the grid with shortage, then stored, then curtailed
    index=d_g_s(:,3)<0;
    consumed_ele(time_ind,index)=d_g_s(index,2); % if generation<demand comsumed=generation
    consumed_ele(time_ind,~index)=d_g_s(~index,1);% if generation>demand comsumed=demand

    %trans_regional dispatch
    %gg_ind=gg_ind+1
    for gg_ind=1:20
        if d_g_s(gg_ind,3)<=0
            continue
        end
        %there are surpluses for current grid
        g_costs=all_costs{gg_ind};
        g_paths=all_paths{gg_ind};
        %ad_grid_ind=ad_grid_ind+1
        for ad_grid_ind=1:length(g_paths)
            g_route=g_paths{ad_grid_ind};%g_route(end)   
            if d_g_s(g_route(end),3)>=0
                continue
            end
            % shortage occurs for the neighboring grid
            g_capacities = calculatePathCapacity(g_route,trans_power);
            if g_capacities<=0
                continue
            end
            % compare the received amount considering losses, and trans capacity
            % compare the available ele in the staring grid
            t_amount=min(min(abs(d_g_s(g_route(end),3))/(1-g_costs(ad_grid_ind)),g_capacities),d_g_s(gg_ind,3));
            % record shifted ele
            shifted_ele(time_ind,gg_ind,g_route(end))=shifted_ele(time_ind,gg_ind,g_route(end))+t_amount;
            % update surplus/shortage state
            d_g_s(gg_ind,3)=d_g_s(gg_ind,3)-t_amount; % residual surplus after shifting
            d_g_s(g_route(end),3)=d_g_s(g_route(end),3)+t_amount*(1-g_costs(ad_grid_ind));% remaining shortage after shifting
            %update trans capacities of all routes
            for j = 1:(length(g_route) - 1)
                trans_power(g_route(j),g_route(j + 1))=trans_power(g_route(j),g_route(j + 1))-t_amount;
            end
        end
    end
    % storage system
    for gg_ind=1:20
        if d_g_s(gg_ind,3)>=0%Store
            % consider the limit of maximum storage operating power and maximum storage capacity
            t_amount=min(min(d_g_s(gg_ind,3),storagePow(gg_ind)),(storageCap(gg_ind)-stored_ele(time_ind,gg_ind))/toStorageLoss);
            stored_ele(time_ind+1,gg_ind)=stored_ele(time_ind,gg_ind)+t_amount*toStorageLoss;
            curtailed_ele(time_ind,gg_ind)=d_g_s(gg_ind,3)-t_amount;
            % curtailed equals the surplus minus the actual storage
            d_g_s(gg_ind,3)=0;
        else%Release
            t_amount=min(min(storagePow(gg_ind)/fromStorageLoss,abs(d_g_s(gg_ind,3))),stored_ele(time_ind,gg_ind));
            stored_ele(time_ind+1,gg_ind)=max(stored_ele(time_ind,gg_ind)-t_amount,0);
            flexible_ele(time_ind,gg_ind)=abs(d_g_s(gg_ind,3)+t_amount);
            d_g_s(gg_ind,3)=0;
        end
    end    
end

%total costs
load NonlConData.mat nonlsol
obj_cost=0;
index=find((CGrid_Index(:,3)==1)&(CGrid_Index(:,2)==1));%offshore wind
obj_cost=obj_cost+3461*sum(ins_cap(index(index>nonlsol)));%USD billion
index=find((CGrid_Index(:,1)>8)&(CGrid_Index(:,1)<14)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));%Asia
obj_cost=obj_cost+927.6*sum(ins_cap(index(index<=nonlsol)));%USD billion
obj_cost=obj_cost+1313*sum(ins_cap(index(index>nonlsol)));%USD billion
index=find((CGrid_Index(:,1)==1)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));%North America
obj_cost=obj_cost+1012.6*sum(ins_cap(index(index<=nonlsol)));%USD billion
obj_cost=obj_cost+1284.8*sum(ins_cap(index(index>nonlsol)));%USD billion
index=find((CGrid_Index(:,1)>4)&(CGrid_Index(:,1)<9)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));%Europe
obj_cost=obj_cost+1075.9*sum(ins_cap(index(index<=nonlsol)));%USD billion
obj_cost=obj_cost+1650.4*sum(ins_cap(index(index>nonlsol)));%USD billion
index=find((CGrid_Index(:,1)>1)&(CGrid_Index(:,1)<5)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));%Latin America
obj_cost=obj_cost+861.4*sum(ins_cap(index(index<=nonlsol)));%USD billion
obj_cost=obj_cost+1499.4*sum(ins_cap(index(index>nonlsol)));%USD billion
index=find((CGrid_Index(:,1)>15)&(CGrid_Index(:,1)<21)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));%Africa
obj_cost=obj_cost+1256.6*sum(ins_cap(index(index<=nonlsol)));%USD billion
obj_cost=obj_cost+1684.7*sum(ins_cap(index(index>nonlsol)));%USD billion
index=find((CGrid_Index(:,1)>13)&(CGrid_Index(:,1)<16)&(CGrid_Index(:,2)==1)&(CGrid_Index(:,3)==0));%Oceania
obj_cost=obj_cost+922.5*sum(ins_cap(index(index<=nonlsol)));%USD billion
obj_cost=obj_cost+1360.7*sum(ins_cap(index(index>nonlsol)));%USD billion
trans_power=zeros(20,20);
trans_power(trans_connections==1)=scale(length(CGrid_Index)+41:end)/1000; %transmission power TW
obj_cost=obj_cost+98*sum(trans_power(:));%USD billion
obj_cost=obj_cost+350*sum(storageCap(:));%Storage (USD billion)
f(1)=sum(curtailed_ele(:))./sum(grid_gens(:));%cr;
f(2)=sum(flexible_ele(:))./sum(loads(:));%1-pr
f(3)=obj_cost;%cost
% f(3) = abs(sum(scale(1:length(CGrid_Index))) - 0.35 * length(CGrid_Index))/length(CGrid_Index);    
con=consumed_ele;
flex=flexible_ele;
curtail=curtailed_ele;
storage=stored_ele;
shifted=shifted_ele;
end