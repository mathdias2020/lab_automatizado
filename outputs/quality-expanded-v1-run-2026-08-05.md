# Primeiro run reproduzível do executor

**Run:** `quality_expanded_v1`  
**Projeto:** Laboratório Automatizado (`lab_automatizado`)  
**Tipo:** qualidade de dados e benchmark de leitura  
**Status:** sucesso

## Resultado

- 697.179.363 registros lidos;
- 2 ativos: WDOFUT e WINFUT;
- 2 schemas: `legacy` e `recent`;
- 16 arquivos de origem;
- cobertura observada: 2012-04-02 a 2026-06-30;
- duração medida: 79,96 segundos;
- container descartável removido ao final;
- diretório temporário limpo;
- nenhum Supabase acessado;
- nenhuma ordem enviada.

## Recursos efetivos

- imagem DuckDB fixada por digest;
- 1,5 vCPU;
- 2 GB de limite do container;
- 1 thread DuckDB;
- 1.500 MB de memória interna DuckDB;
- spill temporário em pasta exclusiva no disco;
- rede desabilitada;
- dados de entrada somente leitura.

## Artefatos

- `partition_quality.csv`: quatro combinações ativo/schema, sem nulos nos campos essenciais;
- `source_quality.csv`: 16 arquivos com contagem, intervalo temporal, preço mínimo/máximo e linhas editadas;
- `run_summary.csv`: resumo global e versão DuckDB;
- `quality-expanded-v1-run-manifest.json`: configuração, hashes e checks do run.

## Conclusão

O ciclo mínimo do laboratório está comprovado: manifesto → container isolado → DuckDB → artefatos auditáveis → limpeza. O executor está pronto para receber uma primeira métrica de pesquisa, mas ainda não há descoberta ou validação de estratégia neste run.
