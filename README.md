

##デモアプリのビルド手順(windowsの場合)

###1、source treeを起動してビルドするフォルダーをダウンロードする。

  
  1. 新規クローンを作成する
  
  2.元のパスに<https://github.com/tmishima/Hinecraft.git>を指定する
  
  3.保存先のパスにそれ専用のフォルダーを作成して、それを指定する。


###2、コマンドでビルドを始める。

　1.コマンドを起動して保存パスに指定したディレクトリーへ移動する。

　2.`cabal clean`を実行

　3.`cabal configure`を実行する

　　3-1.エラーメッセージが出た場合
　　


注釈１
      

　4.`cabal build`を実行する。実行が成功すると、distフォルダーに実行ファイルが出来る。

　5.実行ファイルを保存パスのフォルダーに移動。


  注釈１
  
    Config file path source is default config file.
  
    Config file C:\Users\k10001kk\AppData\Roaming\cabal\config not found.

    Writing default configuration to

    C:\Users\k10001kk\AppData\Roaming\cabal\config

    Warning: The package list for 'hackage.haskell.org' does not exist. Run 'cabal

    update' to download it.

    Resolving dependencies...

    Configuring Hinecraft-0.2.0.0...

    cabal: At least the following dependencies are missing:
  
    FTGL -any,

    GLFW-b -any,

    GLUtil -any,

    JuicyPixels -any,

    cereal -any,

    linear –any





