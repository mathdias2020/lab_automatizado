# Protocolo de validação do laboratório

Este documento define as regras da pesquisa. Agentes podem propor novas hipóteses, mas não podem alterar silenciosamente este protocolo, acessar o holdout ou mudar a definição de sucesso de um experimento já iniciado.

## 1. Unidade de pesquisa

Cada experimento deve ter:

- `run_id` imutável;
- hipótese e motivação;
- ativo explicitamente definido: WDO ou WIN;
- dataset identificado por snapshot e hash;
- commit do código;
- configuração serializada;
- custos e slippage utilizados;
- período de treino, validação e holdout;
- artefatos e relatório;
- conclusão assinada pelo executor.

## 2. Dados

- O histórico de cinco anos é a base principal para descobrir e validar hipóteses.
- Os trinta dias úteis com maior riqueza de microestrutura podem orientar hipóteses secundárias, mas não podem sustentar sozinhos uma conclusão de longo prazo.
- Séries contínuas ajustadas são aceitas como representação de pesquisa.
- WDO e WIN devem ser processados separadamente.
- Dados ausentes, cobertura insuficiente e campos indisponíveis devem ser registrados como `NULL` ou `SEM_COBERTURA_ESTRUTURAL`.
- Dados originais são somente leitura; qualquer transformação gera um novo artefato com manifesto.

## 3. Separação temporal

A configuração inicial é:

- descoberta: aproximadamente 60% do período elegível;
- validação: aproximadamente 20% do período elegível;
- holdout cego: aproximadamente os 12 meses mais recentes.

As datas exatas serão calculadas somente depois do inventário dos arquivos. O holdout não pode ser usado para escolher indicadores, parâmetros, filtros, horários ou estratégias.

## 4. Causalidade

O executor deve impedir lookahead em:

- features;
- labels;
- normalizações;
- seleção de parâmetros;
- stops e saídas;
- agregações intradiárias;
- custos e slippage;
- seleção de amostras.

Qualquer transformação que use informação futura deve ser marcada como inválida e impedir a promoção do resultado.

## 5. Custos e execução de pesquisa

Todo resultado deve informar, separadamente:

- retorno bruto;
- corretagem e emolumentos considerados;
- slippage considerado;
- retorno após custos;
- número de operações;
- distribuição de ganhos e perdas;
- drawdown;
- concentração temporal;
- exposição por ativo.

Esta fase não executa replay da ProfitDLL, ordens em corretora ou simulador operacional. O backtest histórico é uma ferramenta de pesquisa e deve declarar suas simplificações de execução.

## 6. Múltiplos testes e robustez

O relatório deve informar:

- quantidade de hipóteses testadas;
- quantidade de combinações de parâmetros;
- quantos resultados foram descartados;
- quais filtros foram aplicados depois de observar resultados;
- desempenho em janelas e subperíodos;
- sensibilidade a custos, slippage e parâmetros;
- evidência contra overfitting e data snooping.

Quando aplicável, a análise deve considerar Reality Check/SPA, Deflated Sharpe Ratio, PBO/CSCV ou métodos equivalentes previamente registrados.

## 7. Frequência

Cinco operações semanais é uma meta média do portfólio, não uma obrigação do agente. Uma estratégia não pode ser alterada ou forçada a operar somente para atingir essa frequência.

## 8. Critério de saída do laboratório

Um resultado só pode ser classificado como candidato à promoção quando:

1. o experimento for reproduzível;
2. não houver violação de causalidade;
3. houver cobertura válida nos períodos analisados;
4. o resultado sobreviver à validação fora da amostra;
5. custos e slippage estiverem explicitados;
6. a robustez e os múltiplos testes forem analisados;
7. o holdout for processado somente na etapa autorizada;
8. houver aprovação humana documentada.

O protocolo não garante lucro. Ele define o padrão mínimo para não confundir uma descoberta estatística frágil com uma estratégia pronta para operar.
