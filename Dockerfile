FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator

# Minimal deps only
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget unzip openjdk-17-jre-headless \
    python3 python3-pip \
    xvfb x11vnc \
    supervisor \
    libgl1 libgles2 libpulse0 libnss3 libxss1 libxtst6 \
    libxrandr2 libasound2 libatk1.0-0 libgtk-3-0 \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# websockify
RUN pip3 install --no-cache-dir websockify

# Android SDK cmdline-tools only
RUN mkdir -p $ANDROID_HOME/cmdline-tools && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/ct.zip && \
    unzip -q /tmp/ct.zip -d /tmp && \
    mv /tmp/cmdline-tools $ANDROID_HOME/cmdline-tools/latest && \
    rm /tmp/ct.zip

# Install only what's needed — no Google APIs (saves ~1GB), use AOSP image
RUN yes | sdkmanager --licenses > /dev/null && \
    sdkmanager --install \
      "platform-tools" \
      "emulator" \
      "system-images;android-30;default;x86_64"

# Create AVD — Android 11 AOSP (much smaller than 14)
RUN echo "no" | avdmanager create avd \
    -n android_device \
    -k "system-images;android-30;default;x86_64" \
    --device "pixel" \
    --force

# Tune AVD for low-resource server
RUN echo "hw.ramSize=1536\nhw.gpu.enabled=no\nhw.gpu.mode=swiftshader_indirect\nhw.lcd.width=720\nhw.lcd.height=1280\nhw.lcd.density=320\nvm.heapSize=256\ndisk.dataPartition.size=2048M\nhw.keyboard=yes\nshowDeviceFrame=no\nfastboot.forceColdBoot=no\nhw.mainKeys=no" \
    >> /root/.android/avd/android_device.avd/config.ini

# noVNC (just the essentials)
RUN mkdir -p /opt/novnc && \
    wget -q https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz -O /tmp/novnc.tar.gz && \
    tar -xzf /tmp/novnc.tar.gz -C /opt/novnc --strip-components=1 && \
    rm /tmp/novnc.tar.gz

# Node app
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 3000

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
