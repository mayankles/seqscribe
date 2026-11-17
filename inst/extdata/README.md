# Demo datasets

Chosen 2026-11-16. Nothing is bundled yet; the prototype should load these
from their Bioconductor packages or GEO, with a "use a local file" path.

| Role | Dataset | Source | Why |
|---|---|---|---|
| Prototype demo | airway (GSE52778): 8 samples, 4 human airway smooth muscle cell lines, control vs dexamethasone | Bioconductor `airway` package (includes the GEO series matrix) | Small, clean, real GEO metadata for the sample parser; cell line is a blocking factor for the design |
| Batch covariate, small | pasilla (GSE18508): 7 Drosophila samples, knock-down vs untreated, mixed single-read and paired-end libraries | Bioconductor `pasilla` package | Smallest realistic case of a technical covariate that belongs in the design |
| Batch correction, real | GFRN pathway activation (GSE83083, GSE59765): 47 human mammary epithelial samples in 3 batches | GEO; analysis code at github.com/zhangyuqing/ComBat-seq | The ComBat-seq paper's example. Each treatment is in one batch only and GFP controls are in all three, so it also tests the confounding checks |

Not yet verified: the format of the count files available for the GFRN
series on GEO.
