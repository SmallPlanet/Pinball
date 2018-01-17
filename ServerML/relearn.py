from __future__ import division

import train
import heatmap

#heatmap.ExportAnimatedHeatmapForAllImages("TrainingHeatmap.gif")

train.RelearnAllRunsFromScratch()
train.EvaluateAllRuns()


