clear,clc
data=importdata('Benefits_Data_Summary.xlsx');
data=data.data.EnergyInequality;

tmpdata=data(:,[3,7,11]);
[~,ind2]=sort(tmpdata(:,3));
tmpdata=tmpdata(ind2,:);
tmpdata(:,4)=tmpdata(:,1)/sum(tmpdata(:,1));
tmpdata(:,5)=2*(cumsum(tmpdata(:,2),1)/sum(tmpdata(:,2)));
tmpdata(:,6)=tmpdata(:,2)/sum(tmpdata(:,2));
tmpdata(:,7)=tmpdata(:,4).*(tmpdata(:,5)-tmpdata(:,6));
gini_cof(1)=1-sum(tmpdata(:,7));
tmpdata(:,1:3) = cumsum(tmpdata(:,1:3),1);
tmpdata(:,1)=tmpdata(:,1)/tmpdata(end,1);
tmpdata(:,2)=tmpdata(:,2)/tmpdata(end,2);
figure,plot(tmpdata(:,1),tmpdata(:,2),'-o')

tmpdata=data(:,[3,6,10]);
[~,ind2]=sort(tmpdata(:,3));
tmpdata=tmpdata(ind2,:);
tmpdata(:,4)=tmpdata(:,1)/sum(tmpdata(:,1));
tmpdata(:,5)=2*(cumsum(tmpdata(:,2),1)/sum(tmpdata(:,2)));
tmpdata(:,6)=tmpdata(:,2)/sum(tmpdata(:,2));
tmpdata(:,7)=tmpdata(:,4).*(tmpdata(:,5)-tmpdata(:,6));
gini_cof(2)=1-sum(tmpdata(:,7));
tmpdata(:,1:3) = cumsum(tmpdata(:,1:3),1);
tmpdata(:,1)=tmpdata(:,1)/tmpdata(end,1);
tmpdata(:,2)=tmpdata(:,2)/tmpdata(end,2);
hold on,plot(tmpdata(:,1),tmpdata(:,2))

tmpdata=data(:,[3,5,9]);
[~,ind2]=sort(tmpdata(:,3));
tmpdata=tmpdata(ind2,:);
tmpdata(:,4)=tmpdata(:,1)/sum(tmpdata(:,1));
tmpdata(:,5)=2*(cumsum(tmpdata(:,2),1)/sum(tmpdata(:,2)));
tmpdata(:,6)=tmpdata(:,2)/sum(tmpdata(:,2));
tmpdata(:,7)=tmpdata(:,4).*(tmpdata(:,5)-tmpdata(:,6));
gini_cof(3)=1-sum(tmpdata(:,7));
tmpdata(:,1:3) = cumsum(tmpdata(:,1:3),1);
tmpdata(:,1)=tmpdata(:,1)/tmpdata(end,1);
tmpdata(:,2)=tmpdata(:,2)/tmpdata(end,2);
hold on,plot(tmpdata(:,1),tmpdata(:,2))

tmpdata=data(:,[3,4,8]);
[~,ind2]=sort(tmpdata(:,3));
tmpdata=tmpdata(ind2,:);
tmpdata(:,4)=tmpdata(:,1)/sum(tmpdata(:,1));
tmpdata(:,5)=2*(cumsum(tmpdata(:,2),1)/sum(tmpdata(:,2)));
tmpdata(:,6)=tmpdata(:,2)/sum(tmpdata(:,2));
tmpdata(:,7)=tmpdata(:,4).*(tmpdata(:,5)-tmpdata(:,6));
gini_cof(4)=1-sum(tmpdata(:,7));
tmpdata(:,1:3) = cumsum(tmpdata(:,1:3),1);
tmpdata(:,1)=tmpdata(:,1)/tmpdata(end,1);
tmpdata(:,2)=tmpdata(:,2)/tmpdata(end,2);
hold on,plot(tmpdata(:,1),tmpdata(:,2))
hold on,plot([0 1],[0 1],'k-')
legend({'Independent','Neighbour','Continent','Global','1:1'})




