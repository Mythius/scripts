# run as sh setup.sh
sudo apt install curl 
curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | bash 
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install node
cd $HOME
git clone https://github.com/mythius/videostream
cd $HOME/videostream
npm i
cd $HOME/scripts
cat > "$HOME/videostream/server.sh" << EOF
cd $HOME/videostream
EOF
printf "%s server.js\n" "$(which node)" >> "$HOME/videostream/server.sh"
sudo bash createServiceFile.sh stream "$HOME/videostream/server.sh"
sudo bash $HOME/videostream/diskrip/install_dependencies.sh
sudo systemctl enable ripdisk.service
sudo systemctl start ripdisk.service
echo "http://$(hostname -I | awk '{print $1}')"
echo "Videostream setup complete please put a DVD in the diskreader to begin"