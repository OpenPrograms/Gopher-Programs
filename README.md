Gophers-Programs
================

### Contents

#### GML

A gui library, with example programs. In development, fully usable but with only a few gui components implemented so far, already fully capable of doing dialog boxes and basic forms.

See the wiki for documentation, or just head to the /bin directory to look at some sample programs.


#### gitrepo

simple command-line program to pull an entire git repo, all files and directories. Make sure you have enough disk space, and be careful of the rather low unauthorized api usage rate cap on the git api, I didn't feel like making enough sense of OAuth to even determine with certainty whether it's possible to authorize (my gut says no, my head says I'm not sure I'd want to be giving OC my github account credentials anyway).

example:

gitrepo OpenPrograms/Gopher-Programs /hd1/gp

This one is complete DWTFYW license. Steal the code, modify it, extend it, take full credit, whatever. There's a hackish but effective json->lua table converter in there, as well as an unused base64 decoding function which has been tested against github's base64 encoded data included in some gitapi json responses (be sure to strip "\n"s and the trailing "=" from the encoded data first, for some reason github thinks we need neatly line-wrapped base64). Go to town, have fun. 
    
### Contributions

If you want to modify this code, feel free! If you're thinking of sending me pull requests of your modifications... I won't say *don't*, but being a control freak, unless it something we've talked about first and I've agreed to, I'm likely to be annoyed at you, and the fact that I have no sound logical grounds to be annoyed will make me more annoyed, and then you probably won't get a christmas card from me, which will be horribly cruel and completely unfair. 
