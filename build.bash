#!/bin/bash
PATH=`npm bin`:$PATH
jade -Pp index.jade < index.jade |./insanify.ls > index.html
#./insanify.ls < testing.insane.html > testing.html
