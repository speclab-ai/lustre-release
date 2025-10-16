#!/bin/bash
kapi=$7/$1/$2/$3/$5/kapi/include
alternatives --remove grumple ${kapi}
rm -fr $7/$1/$2/$3/$5/kapi
