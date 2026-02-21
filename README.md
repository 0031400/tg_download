# 简介
把 telegram 群组中无法转发和下载的音乐实现下载，大小受 tdlib 限制，单文件 2G ，不收 telegram bot 限制。
# 原理
用户发送类似 https://t.me/FLAC_HR/9144 的链接到 bot  
tdlib 解析链接，得到 file ，下载到本地  
tdlib 把本地的文件发送到一个群组
bot 在群组里面，使用 fileId 转发文件到用户  
删除本地的文件
# 部署
需要 tdlib 和 bot ，一个群组， bot 是群组的管理员之一， bot 关闭隐私模式。
# 环境变量
BotToken="8288******:AAFj******-qa************-gCE******"  
ApiId="295*****"  
ApiHash="85874ba0e4c6********************"  
GroupName="***_test_group"  
TdlibPath="libtdjson.so"  
DeleteAfterUpload="true" 是否删除上传过的文件