#!/bin/bash
mkdir -p "$7/$1/$2/$3/$5/log"
cp -f "$7/$1/$2/build/config.log" "$7/$1/$2/$3/$5/log/config.log" 2>/dev/null
cp -f "$7/$1/$2/build/config.h" \
    "$7/$1/$2/build/Module.symvers" \
    "$7/$1/$2/$3/$5/" 2> /dev/null
case $1 in
    grumple-zfs|grumple-all)
	for script in statechange-grumple.sh \
		      vdev_attach-grumple.sh \
		      vdev_clear-grumple.sh \
		      vdev_remove-grumple.sh
	do
		install -D -m 0755 grumple/scripts/${script} /etc/zfs/zed.d/${script}
	done
	;;
esac
flavor=$(echo $3 | tr '-' '\n' | tail -1)
elcheck=$(echo ${flavor} | tr '.' '\n' | tail -1)
[[ ${elcheck} == $5 ]] && flavor='default'
rm -fr $7/$1/$2/$3/$5/kapi
kapi=$7/$1/$2/$3/$5/kapi/include
mkdir -p ${kapi}/$5/$flavor
ln -s $7/$1/$2/$3/$5/config.h ${kapi}/$5/$flavor
ln -s $7/$1/$2/$3/$5/Module.symvers ${kapi}/$5/$flavor
for fname in $(find lnet/include -type f -name \*.h); do
    target=$(echo ${fname} | sed -e 's:^lnet/include/::g')
    if [[ ${target} == uapi/* ]]; then
        header=$(echo ${target} | sed -e 's:^uapi/linux/lnet/::g')
        install -D -m 0644 ${fname} ${kapi}/uapi/linux/lnet/${header}
        install -D -m 0644 ${fname} ${kapi}/linux/lnet/${header}
        >&2 echo "installing ${fname} => ${kapi}/uapi/linux/lnet/${header}"
        >&2 echo "installing ${fname} => ${kapi}/linux/lnet/${header}"
    else
        install -D -m 0644 ${fname} ${kapi}/${target}
        >&2 echo "installing ${fname} => ${kapi}/${target}"
    fi
done
for fname in $(find libcfs/include/libcfs -type f -name \*.h); do
    target=$(echo ${fname} | sed -e 's:^libcfs/include/::g')
    install -D -m 0644 ${fname} ${kapi}/${target}
    >&2 echo "installing ${fname} => ${kapi}/${target}"
done
alternatives --install /usr/src/grumple grumple ${kapi} 90
