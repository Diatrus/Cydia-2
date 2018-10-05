.DELETE_ON_ERROR:
.SECONDARY:

dpkg := fakeroot dpkg-deb -Zlzma
version := $(shell ./version.sh)

flag := 
plus :=
link := 
libs := 

gxx := xcrun --sdk iphoneos g++
cycc := $(gxx)

sdk := $(shell xcodebuild -sdk iphoneos -version Path)
cycc += -idirafter /usr/include
cycc += -F$(sdk)/System/Library/PrivateFrameworks

ARCHS := armv6 arm64
cycc += $(foreach arch,$(ARCHS),-arch $(arch))

ifeq ("$(findstring armv6,$(ARCHS))","armv6")
cycc += -Xarch_armv6 -miphoneos-version-min=5.0
endif
cycc += -Xarch_arm64 -miphoneos-version-min=7.0

cycc += -fmessage-length=0
cycc += -gfull -O2
cycc += -fvisibility=hidden

link += -Wl,-dead_strip
link += -Wl,-no_dead_strip_inits_and_terms

flag += -Iapt
flag += -Iapt-contrib
flag += -Iapt-deb
flag += -Iapt-extra
flag += -Iapt-tag

flag += -I.
flag += -isystem sysroot/usr/include

flag += -idirafter icu/icuSources/common
flag += -idirafter icu/icuSources/i18n

flag += -Wall
flag += -Wno-dangling-else
flag += -Wno-deprecated-declarations
flag += -Wno-objc-protocol-method-implementation
flag += -Wno-logical-op-parentheses
flag += -Wno-shift-op-parentheses
flag += -Wno-unknown-pragmas
flag += -Wno-unknown-warning-option

plus += -fobjc-call-cxx-cdtors
plus += -fvisibility-inlines-hidden

link += -multiply_defined suppress

libs += -framework CoreFoundation
libs += -framework CoreGraphics
libs += -framework Foundation
libs += -framework GraphicsServices
libs += -framework IOKit
libs += -framework QuartzCore
libs += -framework SpringBoardServices
libs += -framework SystemConfiguration
libs += -framework WebCore
libs += -framework WebKit

libs += Objects/libapt.a
libs += -licucore

uikit := 
uikit += -framework UIKit

dirs := Menes CyteKit Cydia SDURLCache

code := $(foreach dir,$(dirs),$(wildcard $(foreach ext,h hpp c cpp m mm,$(dir)/*.$(ext))))
code := $(filter-out SDURLCache/SDURLCacheTests.m,$(code))
code += MobileCydia.mm Version.mm iPhonePrivate.h Cytore.hpp lookup3.c Sources.h Sources.mm DiskUsage.cpp

source := $(filter %.m,$(code)) $(filter %.mm,$(code))
source += $(filter %.c,$(code)) $(filter %.cpp,$(code))
header := $(filter %.h,$(code)) $(filter %.hpp,$(code))

object := $(source)
object := $(object:.c=.o)
object := $(object:.cpp=.o)
object := $(object:.m=.o)
object := $(object:.mm=.o)
object := $(object:%=Objects/%)

libapt := 
libapt += $(wildcard apt/apt-pkg/*.cc)
libapt += $(wildcard apt/apt-pkg/deb/*.cc)
libapt += $(wildcard apt/apt-pkg/contrib/*.cc)
libapt += apt-tag/apt-pkg/tagfile-keys.cc
libapt += apt/methods/store.cc
libapt := $(filter-out %/srvrec.cc,$(libapt))
libapt := $(patsubst %.cc,Objects/%.o,$(libapt))

link += -Wl,-lz,-liconv

flag += -DAPT_PKG_EXPOSE_STRING_VIEW
flag += -Dsighandler_t=sig_t

aptc := $(cycc) $(flag)
aptc += -Wno-deprecated-register
aptc += -Wno-unused-private-field
aptc += -Wno-unused-variable

ifeq ($(findstring armv6,$(ARCHS)),"armv6")
flag += -Xarch_armv6 -marm # @synchronized
flag += -Xarch_armv6 -mcpu=arm1176jzf-s
flag += -Xarch_armv6 -ffixed-r9
link += -Xarch_armv6 -Wl,-lgcc_s.1
link += -Xarch_armv6 -Wl,-segalign,4000
endif

plus += -std=c++11
plus += -stdlib=libc++
#link += libcxx/lib/libc++.a

images := $(shell find MobileCydia.app/ -type f -name '*.png')
images := $(images:%=Images/%)

lproj_deb := debs/cydia-lproj_$(version)_iphoneos-arm.deb

all: MobileCydia

clean:
	rm -f MobileCydia postinst cydo setnsfpn cfversion
	rm -rf Objects/ Images/

Objects/%.o: %.cc $(header) apt-extra/*.h
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(aptc) $(plus) -c -o $@ $< -Dmain=main_$(basename $(notdir $@))

Objects/%.o: %.c $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) -c -o $@ -x c $< $(flag)

Objects/%.o: %.m $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) -c -o $@ $< $(flag)

Objects/%.o: %.cpp $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) $(plus) -c -o $@ $< $(flag)

Objects/%.o: %.mm $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) $(plus) -c -o $@ $< $(flag)

Objects/Version.o: Version.h

Images/%.png: %.png
	@mkdir -p $(dir $@)
	@echo "[pngc] $<"
	@./pngcrush.sh $< $@

sysroot: sysroot.sh
	@echo "Your ./sysroot/ is either missing or out of date. Please read compiling.txt for help." 1>&2
	@echo 1>&2
	@exit 1

Objects/libapt.a: $(libapt)
	@echo "[create] $@"
	@libtool -static -o $@ $^

MobileCydia: sysroot Objects/libapt.a $(object) entitlements.xml # Objects/UIKit.tbd
	@echo "[link] $@"
	@$(cycc) -o $@ $(filter %.o,$^) $(link) $(plus) $(libs) $(uikit) -Wl,-sdk_version,11.0
	@mkdir -p bins
	@cp -a $@ bins/$@-$(version)_$(shell date +%s)
	@echo "[strp] $@"
	@grep '~' <<<"$(version)" >/dev/null && echo "skipping..." || strip $@
	@echo "[uikt] $@"
	@./uikit.sh $@
	@echo "[sign] $@"
	@ldid -T0 -Sentitlements.xml $@ || { rm -f $@ && false; }

cfversion: cfversion.mm
	$(cycc) -o $@ $(filter %.mm,$^) $(flag) $(link) -framework CoreFoundation
	@ldid -T0 -Sgenent.xml $@

setnsfpn: setnsfpn.cpp
	$(cycc) -o $@ $(filter %.cpp,$^) $(flag) $(link)
	@ldid -T0 -Sgenent.xml $@

cydo: cydo.cpp
	$(cycc) $(plus) -o $@ $(filter %.cpp,$^) $(flag) $(link) -Wno-deprecated-writable-strings
	@ldid -T0 -Sgenent.xml $@

postinst: postinst.mm CyteKit/stringWithUTF8Bytes.mm CyteKit/stringWithUTF8Bytes.h CyteKit/UCPlatform.h
	$(cycc) $(plus) -o $@ $(filter %.mm,$^) $(flag) $(link) -framework CoreFoundation -framework Foundation -framework UIKit
	@ldid -T0 -Sgenent.xml $@

debs/cydia_$(version)_iphoneos-arm.deb: MobileCydia preinst postinst cfversion setnsfpn cydo $(images) $(shell find MobileCydia.app) cydia.control Library/firmware.sh Library/move.sh Library/startup
	fakeroot rm -rf _
	mkdir -p _/var/lib/cydia
	
	mkdir -p _/etc/apt
	cp -a Trusted.gpg _/etc/apt/trusted.gpg.d
	cp -a Sources.list _/etc/apt/sources.list.d
	
	mkdir -p _/usr/libexec
	cp -a Library _/usr/libexec/cydia
	cp -a sysroot/usr/bin/du _/usr/libexec/cydia
	cp -a cfversion _/usr/libexec/cydia
	cp -a setnsfpn _/usr/libexec/cydia
	
	cp -a cydo _/usr/libexec/cydia
	
	mkdir -p _/Library
	cp -a LaunchDaemons _/Library/LaunchDaemons
	
	mkdir -p _/Applications
	cp -a MobileCydia.app _/Applications/Cydia.app
	rm -rf _/Applications/Cydia.app/*.lproj
	cp -a MobileCydia _/Applications/Cydia.app/Cydia
	ln -s Cydia _/Applications/Cydia.app/store
	
	cd MobileCydia.app && find . -name '*.png' -exec cp -af ../Images/MobileCydia.app/{} ../_/Applications/Cydia.app/{} ';'
	
	mkdir -p _/Applications/Cydia.app/Sources
	ln -s /usr/share/bigboss/icons/bigboss.png _/Applications/Cydia.app/Sources/apt.bigboss.us.com.png
	ln -s /usr/share/bigboss/icons/planetiphones.png _/Applications/Cydia.app/Sections/"Planet-iPhones Mods.png"
	
	mkdir -p _/DEBIAN
	./control.sh cydia.control _ >_/DEBIAN/control
	cp -a preinst postinst triggers _/DEBIAN/
	
	find _ -exec touch -t "$$(date -j -f "%s" +"%Y%m%d%H%M.%S" "$$(git show --format='format:%ct' | head -n 1)")" {} ';'
	
	fakeroot chown -R 0 _
	fakeroot chgrp -R 0 _
	fakeroot chmod 6755 _/usr/libexec/cydia/cydo
	
	mkdir -p debs
	ln -sf debs/cydia_$(version)_iphoneos-arm.deb Cydia.deb
	$(dpkg) -b _ Cydia.deb
	@echo "$$(stat -L -f "%z" Cydia.deb) $$(stat -f "%Y" Cydia.deb)"

$(lproj_deb): $(shell find MobileCydia.app -name '*.strings') cydia-lproj.control
	fakeroot rm -rf __
	mkdir -p __/Applications/Cydia.app
	
	cp -a MobileCydia.app/*.lproj __/Applications/Cydia.app
	
	mkdir -p __/DEBIAN
	./control.sh cydia-lproj.control __ >__/DEBIAN/control
	
	fakeroot chown -R 0 __
	fakeroot chgrp -R 0 __
	
	mkdir -p debs
	ln -sf debs/cydia-lproj_$(version)_iphoneos-arm.deb Cydia_.deb
	$(dpkg) -b __ Cydia_.deb
	@echo "$$(stat -L -f "%z" Cydia_.deb) $$(stat -f "%Y" Cydia_.deb)"
	
package: debs/cydia_$(version)_iphoneos-arm.deb $(lproj_deb)

.PHONY: all clean package
