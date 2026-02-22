FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator

# All deps in one layer, clean immediately
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget unzip openjdk-17-jre-headless \
    python3 python3-pip \
    xvfb x11vnc supervisor \
    libgl1 libgles2 libpulse0 libnss3 \
    libxss1 libxtst6 libxrandr2 libasound2 \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && pip3 install --no-cache-dir websockify \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Android SDK cmdline-tools
RUN wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/ct.zip \
    && unzip -q /tmp/ct.zip -d /tmp \
    && mkdir -p $ANDROID_HOME/cmdline-tools \
    && mv /tmp/cmdline-tools $ANDROID_HOME/cmdline-tools/latest \
    && rm /tmp/ct.zip

# Install emulator + smallest possible system image (API 28, no Google APIs, no ARM)
RUN yes | sdkmanager --licenses > /dev/null \
    && sdkmanager "platform-tools" "emulator" "system-images;android-28;default;x86" \
    && rm -rf $ANDROID_HOME/emulator/lib64/qt /tmp/* \
    && find $ANDROID_HOME -name "*.pdb" -delete

# Create AVD
RUN echo "no" | avdmanager create avd \
    -n avd \
    -k "system-images;android-28;default;x86" \
    --force \
    && echo "hw.ramSize=1024\nhw.gpu.enabled=no\nhw.gpu.mode=swiftshader_indirect\nhw.lcd.width=540\nhw.lcd.height=960\nhw.lcd.density=240\nvm.heapSize=192\ndisk.dataPartition.size=1024M\nhw.keyboard=yes\nshowDeviceFrame=no\nfastboot.forceColdBoot=no\nhw.mainKeys=no\nhw.camera.back=none\nhw.camera.front=none\nhw.audioInput=no\nhw.audioOutput=no\nhw.gps=no\nhw.sensors.proximity=no\nhw.sensors.light=no\nhw.sensors.gyroscope=no\nhw.sensors.magnetic_field=no" \
    >> /root/.android/avd/avd.avd/config.ini

# noVNC minimal (core files only)
RUN mkdir -p /opt/novnc/core /opt/novnc/vendor \
    && wget -q https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz -O /tmp/n.tar.gz \
    && tar -xzf /tmp/n.tar.gz -C /tmp \
    && cp -r /tmp/noVNC-1.4.0/core /opt/novnc/ \
    && cp -r /tmp/noVNC-1.4.0/vendor /opt/novnc/ \
    && cp /tmp/noVNC-1.4.0/vnc.html /opt/novnc/ \
    && cp /tmp/noVNC-1.4.0/vnc_lite.html /opt/novnc/ \
    && rm -rf /tmp/*

WORKDIR /app
COPY package.json ./
RUN npm install && npm cache clean --force
COPY . .
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 3000
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
