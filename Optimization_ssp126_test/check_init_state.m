%% check_init_state.m
load Global_Init_State cur_solar cur_wind
fprintf('cur_solar total: %.0f MW = %.0f GW\n', sum(cur_solar), sum(cur_solar)/1000);
fprintf('cur_wind total: %.0f MW = %.0f GW\n', sum(cur_wind), sum(cur_wind)/1000);
fprintf('\ncur_solar per region (GW):\n');
for i=1:20, fprintf('  Region %2d: %.1f GW\n', i, cur_solar(i)/1000); end
fprintf('\ncur_wind per region (GW):\n');
for i=1:20, fprintf('  Region %2d: %.1f GW\n', i, cur_wind(i)/1000); end
