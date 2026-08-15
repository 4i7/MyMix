# Compatibility entry point kept stable for Optimize-MyMix.ps1.
# These final stages preserve the low-overhead architecture across future upstream refreshes.
. (Resolve-RepoPath 'tools/Optimize-MyMix/15-lightweight-controls-final.ps1')
. (Resolve-RepoPath 'tools/Optimize-MyMix/16-appinfo-exit-race.ps1')
