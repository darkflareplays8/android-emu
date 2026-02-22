FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:0
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    unzip \
    openjdk-17-jdk \
    python3 \
    python3-pip \
    xvfb \
    x11vnc \
    supervisor \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    libgles2-mesa \
    libpulse0 \
    libnss3 \
    libxss1 \
    libxtst6 \
    libxrandr2 \
    libasound2 \
    libatk1.0-0 \
    libgtk-3-0 \
    qemu-kvm \
    cpu-checker \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Install websockify for VNC-over-WebSocket
RUN pip3 install websockify

# Install Android SDK command-line tools
RUN mkdir -p $ANDROID_HOME/cmdline-tools && \
    cd /tmp && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmdline-tools.zip && \
    unzip -q cmdline-tools.zip && \
    mv cmdline-tools $ANDROID_HOME/cmdline-tools/latest && \
    rm cmdline-tools.zip

# Accept licenses and install emulator + system image
RUN yes | sdkmanager --licenses && \
    sdkmanager "platform-tools" "emulator" && \
    sdkmanager "system-images;android-34;google_apis;x86_64"

# Create AVD (Android Virtual Device)
RUN echo "no" | avdmanager create avd \
    -n android_device \
    -k "system-images;android-34;google_apis;x86_64" \
    --device "pixel_6" \
    --force

# Configure AVD for server (no GPU, lower RAM for Railway)
RUN AVD_PATH=$(ls -d $HOME/.android/avd/*.avd 2>/dev/null || echo "/root/.android/avd/android_device.avd") && \
    mkdir -p /root/.android/avd/android_device.avd && \
    echo "hw.ramSize=2048\nhw.gpu.enabled=no\nhw.gpu.mode=swiftshader_indirect\nhw.lcd.width=1080\nhw.lcd.height=1920\nhw.lcd.density=420\nvm.heapSize=512\ndisk.dataPartition.size=4096M\nhw.keyboard=yes\nhw.mainKeys=no\nshowDeviceFrame=no\nfastboot.forceColdBoot=no" >> /root/.android/avd/android_device.avd/config.ini

# Install noVNC
RUN cd /opt && \
    wget -q https://github.com/novnc/noVNC/archive/refs/tags/v1.4.0.tar.gz -O novnc.tar.gz && \
    tar -xzf novnc.tar.gz && \
    mv noVNC-1.4.0 novnc && \
    rm novnc.tar.gz

# Set up Node.js app
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .

# Set up supervisor config
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 3000

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
