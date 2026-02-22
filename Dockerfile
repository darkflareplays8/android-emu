FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator

# Deps + Node + websockify in one layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget unzip ca-certificates \
    openjdk-17-jre-headless \
    xvfb x11vnc supervisor \
    libgl1 libgles2 libpulse0 libnss3 \
    libxss1 libxtst6 libxrandr2 libasound2 \
    python3-websockify \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get purge -y --auto-remove curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && find /usr/share/doc -mindepth 1 -delete \
    && find /usr/share/man -mindepth 1 -delete \
    && find /usr/share/locale -mindepth 1 -not -name 'en*' -delete

# Android SDK cmdline-tools
RUN wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/ct.zip \
    && unzip -q /tmp/ct.zip -d /tmp \
    && mkdir -p $ANDROID_HOME/cmdline-tools \
    && mv /tmp/cmdline-tools $ANDROID_HOME/cmdline-tools/latest \
    && rm /tmp/ct.zip \
    && rm -rf $ANDROID_HOME/cmdline-tools/latest/lib/x86_64 2>/dev/null || true

# Emulator + system image, strip everything possible
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
        $ANDROID_HOME/platform-tools/renderscript \
    && find $ANDROID_HOME -name "*.pdb" -delete \
    && find $ANDROID_HOME -name "*.lib" -delete \
    && find $ANDROID_HOME/system-images -name "*.tar.gz" -delete \
    && rm -rf /tmp/* /root/.android/cache

# Create AVD
RUN echo "no" | avdmanager create avd \
    -n avd \
    -k "system-images;android-27;default;x86" \
    --force \
    && printf "hw.ramSize=1024\nhw.gpu.enabled=no\nhw.gpu.mode=swiftshader_indirect\nhw.lcd.width=540\nhw.lcd.height=960\nhw.lcd.density=240\nvm.heapSize=192\ndisk.dataPartition.size=512M\nhw.keyboard=yes\nshowDeviceFrame=no\nfastboot.forceColdBoot=no\nhw.mainKeys=no\nhw.camera.back=none\nhw.camera.front=none\nhw.audioInput=no\nhw.audioOutput=no\nhw.gps=no\nhw.sensors.proximity=no\nhw.sensors.light=no\nhw.sensors.gyroscope=no\nhw.sensors.magnetic_field=no\nhw.accelerometer=no\nhw.battery=no\n" \
    >> /root/.android/avd/avd.avd/config.ini

# noVNC - only the files the browser actually needs
RUN wget -q https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz -O /tmp/n.tar.gz \
    && tar -xzf /tmp/n.tar.gz -C /tmp \
    && mkdir -p /opt/novnc \
    && cp -r /tmp/noVNC-1.4.0/core /opt/novnc/ \
    && cp -r /tmp/noVNC-1.4.0/vendor /opt/novnc/ \
    && cp /tmp/noVNC-1.4.0/vnc_lite.html /opt/novnc/index.html \
    && rm -rf /tmp/*

WORKDIR /app
COPY package.json ./
RUN npm install && npm cache clean --force
COPY . .
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 3000
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
