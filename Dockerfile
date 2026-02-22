FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget unzip ca-certificates \
    openjdk-17-jre-headless \
    supervisor \
    libgl1 libgles2 libpulse0 libnss3 \
    libxss1 libxtst6 libxrandr2 libasound2 \
    xvfb \
    && wget -q https://deb.nodesource.com/setup_20.x -O /tmp/ns.sh && bash /tmp/ns.sh \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && find /usr/share/doc -mindepth 1 -delete \
    && find /usr/share/man -mindepth 1 -delete

# Android SDK
RUN wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/ct.zip \
    && unzip -q /tmp/ct.zip -d /tmp \
    && mkdir -p $ANDROID_HOME/cmdline-tools \
    && mv /tmp/cmdline-tools $ANDROID_HOME/cmdline-tools/latest \
    && rm /tmp/ct.zip

# Emulator + system image
RUN yes | sdkmanager --licenses > /dev/null \
    && sdkmanager "platform-tools" "emulator" "system-images;android-27;default;x86" \
    && rm -rf \
        $ANDROID_HOME/emulator/lib64/qt \
        $ANDROID_HOME/emulator/lib64/gles_swiftshader \
        $ANDROID_HOME/emulator/resources/Nexus* \
        $ANDROID_HOME/emulator/resources/Galaxy* \
        $ANDROID_HOME/emulator/resources/Wear* \
        $ANDROID_HOME/emulator/resources/tv* \
        $ANDROID_HOME/emulator/qemu/darwin* \
        $ANDROID_HOME/emulator/qemu/windows* \
        $ANDROID_HOME/platform-tools/systrace \
    && find $ANDROID_HOME -name "*.pdb" -delete \
    && find $ANDROID_HOME -name "*.lib" -delete \
    && rm -rf /tmp/* /root/.android/cache

# Create AVD
RUN echo "no" | avdmanager create avd \
    -n avd \
    -k "system-images;android-27;default;x86" \
    --force \
    && printf "hw.ramSize=1024\nhw.gpu.enabled=no\nhw.gpu.mode=swiftshader_indirect\nhw.lcd.width=540\nhw.lcd.height=960\nhw.lcd.density=240\nvm.heapSize=192\ndisk.dataPartition.size=512M\nhw.keyboard=yes\nshowDeviceFrame=no\nfastboot.forceColdBoot=no\nhw.mainKeys=no\nhw.camera.back=none\nhw.camera.front=none\nhw.audioInput=no\nhw.audioOutput=no\nhw.gps=no\nhw.sensors.proximity=no\nhw.sensors.light=no\nhw.sensors.gyroscope=no\nhw.sensors.magnetic_field=no\nhw.accelerometer=no\nhw.battery=no\n" \
    >> /root/.android/avd/avd.avd/config.ini

WORKDIR /app
COPY package.json ./
RUN npm install && npm cache clean --force
COPY . .
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 3000
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
