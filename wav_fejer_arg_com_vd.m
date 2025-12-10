% Wavelet coherence: parâmetros ionosféricos × (Vd_mean, Vd_storm, Vd_total, PPEF, DDEF)
clc; clear; close all;

% --- 1) Carregar dados ionosféricos (para criar eixo temporal 5 min)
load('mediasionosfericasARG.mat');  % contém foF2, hF, hmF2
N = length(foF2);
start_time = datetime('01-Aug-2017 00:00', 'InputFormat', 'dd-MMM-yyyy HH:mm');
iono_time = start_time + minutes(5*(0:(N-1)));   % 5-min grid

% --- 2) Ler arquivo drift.dat (Vd's, PPEF, DDEF)
disp('Lendo drift.dat ...');
d = importdata('drift.dat');   % assumindo arquivo numérico
Vd_mean  = d(:,3);
Vd_storm = d(:,4);
Vd_total = d(:,5);
PPEF     = d(:,6);
DDEF     = d(:,7);

% criar tempo do drift (15 min)
nV = length(Vd_mean);
startV = datetime(2017,8,1,0,0,0);
Vd_time = startV + minutes(15*(0:(nV-1)));

% --- 3) Interpolar Vd e campos elétricos para o grid ionosférico (5 min)
x_vd = datenum(Vd_time);
xq = datenum(iono_time);

Vd_mean_interp  = interp1(x_vd, Vd_mean,  xq, 'linear', NaN);
Vd_storm_interp = interp1(x_vd, Vd_storm, xq, 'linear', NaN);
Vd_total_interp = interp1(x_vd, Vd_total, xq, 'linear', NaN);
PPEF_interp     = interp1(x_vd, PPEF,     xq, 'linear', NaN);
DDEF_interp     = interp1(x_vd, DDEF,     xq, 'linear', NaN);

% --- 4) Colocar sinais elétricos em célula
signals = {
    Vd_mean_interp,  'Vd_{mean}';
    Vd_storm_interp, 'Vd_{storm}';
    Vd_total_interp, 'Vd_{total}';
    PPEF_interp,     'PPEF';
    DDEF_interp,     'DDEF';
};

% --- 5) Parâmetros ionosféricos
iono_params = {
    hF(:),   'h''F';
    hmF2(:), 'hmF2';
    foF2(:), 'foF2';
};

% --- 6) Parâmetros para wcoherence
fs = 1/300;    % 1 amostra a cada 300 s = 5 min
dt = 300;      % segundos

% --- 7) Loop: cada parâmetro ionosférico × cada parâmetro elétrico
for p = 1:size(iono_params, 1)
    sig_iono = iono_params{p,1};
    nome_iono = iono_params{p,2};
    
    for k = 1:size(signals, 1)
        sig_vd = signals{k,1};
        nome_vd = signals{k,2};
        
        fprintf('>> Calculando coerência wavelet: %s × %s\n', nome_iono, nome_vd);
        
        % preparar sinais
        sig1 = sig_iono(:);
        sig2 = sig_vd(:);
        
        mask_nan = isnan(sig1) | isnan(sig2);
        sig1_clean = sig1; sig1_clean(isnan(sig1_clean)) = 0;
        sig2_clean = sig2; sig2_clean(isnan(sig2_clean)) = 0;

        % extensão simétrica (igual ao código Ey)
        left1 = flipud(sig1_clean);
        sig1_ext = [left1; left1; sig1_clean; left1; left1];
        left2 = flipud(sig2_clean);
        sig2_ext = [left2; left2; sig2_clean; left2; left2];

        % criar banco de filtros
        fb = cwtfilterbank('SignalLength', numel(sig2_ext), ...
                           'SamplingFrequency', fs, ...
                           'FrequencyLimits', [1e-7 1e-4]);
        
        % calcular coerência wavelet
        [WCOH, ~, period, coi] = wcoherence(sig1_ext, sig2_ext, seconds(dt), 'FilterBank', fb);

        % Cortar parte central igual ao código original (Ey)
        n = length(sig1_clean);
        try
            wcoh_central = WCOH(62:147, 2*n+1:3*n);
            coi_central  = coi(2*n+1:3*n);
            period_sel   = period(62:147,1);
        catch
            disp('Aviso: recorte 62:147 não disponível — usando todas as escalas.');
            wcoh_central = WCOH(:, 2*n+1:3*n);
            coi_central  = coi(2*n+1:3*n);
            period_sel   = period(:,1);
        end

        % aplicar máscara de NaNs
        wcoh_central(:, mask_nan) = NaN;

        % Converter período para dias e eixo log2 invertido
        period_days = days(period_sel);
        period_log = log2(period_days);
        period_lin = flipud(period_days);

        wcoh_central = flipud(wcoh_central);
Wplot = wcoh_central;
Wplot = Wplot / max(Wplot(:));   % agora vai de 0 a 1
        % --- Plot ---
        figure('Name', ['WCOH: ' nome_iono ' × ' nome_vd], 'NumberTitle','off');
h = pcolor(datenum(iono_time), period_lin, Wplot);

        set(h, 'EdgeColor', 'none', 'AlphaData', ~isnan(wcoh_central));
        colormap jet; colorbar;
        set(gca, 'Color', 'w');

        ax = gca;
        ax.YDir = 'normal'; % períodos menores embaixo

        % Escala do eixo X (dias)
        xticks_custom = datenum(datetime(2017,8,1):days(2):datetime(2017,8,31));
        ax.XTick = xticks_custom;
        ax.XTickLabel = datestr(xticks_custom, 'dd');
        ax.XTickLabelRotation = 90;

        % Escala do eixo Y (idêntica ao código Ey)
        periods2 = [0.25 0.5 1 2 4 8 16 31];
        yticks_log2 = log2(periods2);
        ax.YTick = yticks_log2;
        ax.YTickLabel = string(periods2);
        
        
% --- Ajuste de espaçamento vertical (adicionar aqui)
ax.YScale = 'log';         % usa escala logarítmica real (sem deformar)
ax.YTick = [0.25 0.5 1 2 4 8 16 31];
ax.YTickLabel = string(ax.YTick);
ylim([0.25 31]);

ax.MinorGridLineStyle = 'none';   % remove linhas de grade menores (opcional)
ax.YMinorTick = 'off';            % desliga os minor ticks


        xlabel('Time (days)', 'FontSize', 16, 'FontWeight', 'bold');
        ylabel('Period (days)', 'FontSize', 16, 'FontWeight', 'bold');
        title([nome_iono ' × ' nome_vd ' - Araguatins (TO)'], ...
            'FontSize', 16, 'FontWeight', 'bold');

        % Barra de cor
        c = colorbar;
        c.Label.FontSize = 16;
        c.FontSize = 16;
        
        % Ajustar limites e ticks do colorbar para coerência de 0 a 1
c.Limits = [0 1];
c.Ticks = 0.1:0.1:0.9;                % ticks de 0.1 a 1
c.TickLabels = string(c.Ticks);

set(gca, 'Color', 'w');

        % Eixo X igual ao Ey
        xlim([datenum(datetime(2017,8,1)), datenum(datetime(2017,8,31))]);
        
        % Ajustes visuais
        ax.FontSize = 16;
        ax.YDir = 'normal';
        
        disp(['Plot criado: ' nome_iono ' × ' nome_vd]);
        
 % --- Criar pasta 'images' dentro do diretório atual, se não existir
output_dir = fullfile(pwd, 'images');
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

% --- Criar nome do arquivo seguro
safe_nome_iono = nome_iono;
safe_nome_iono = strrep(safe_nome_iono, '''', '');
safe_nome_iono = strrep(safe_nome_iono, '{', '');
safe_nome_iono = strrep(safe_nome_iono, '}', '');
safe_nome_iono = strrep(safe_nome_iono, ' ', '_');

safe_nome_vd = nome_vd;
safe_nome_vd = strrep(safe_nome_vd, '{', '');
safe_nome_vd = strrep(safe_nome_vd, '}', '');
safe_nome_vd = strrep(safe_nome_vd, ' ', '_');

% --- Nome final do arquivo
station = sprintf('WCOH_ARG_%s_%s', safe_nome_iono, safe_nome_vd);

% --- Salvar figura automaticamente
saveas(gcf, fullfile(output_dir, [station '.png']));

    end    
end

disp('Todos os parâmetros ionosféricos plotados com eixos idênticos ao Ey.');
