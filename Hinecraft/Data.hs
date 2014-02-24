{-# LANGUAGE BangPatterns #-}
module Hinecraft.Data
  ( WorldData (..)
  , Chunk (..)
  , SurfaceList
  , SurfacePos
  , getSurface
  , genSurfaceList
  , setSurfaceList
  , getSunLightEffect
  , getChunk
  , genWorldData
  , getBlockID
  , setBlockID
  , calcReGenArea
  , calcSunLight
  , initSunLight
  , calcCursorPos
  ) where

import Data.IORef
import Data.Maybe ( fromJust , catMaybes ,isJust, mapMaybe )
import Data.List
import Data.Ord
import Data.Tuple
import Data.Array.IO
import Control.Monad ( replicateM, forM {- unless,when, void,filterM-} )
import Control.Applicative
import Hinecraft.Types
import Hinecraft.Model
import Hinecraft.Util
import Hinecraft.Render.Util
--import Debug.Trace as Dbg
 
type SurfaceList = IORef [(ChunkNo, [(BlockNo,IORef SurfacePos)])]

data ChunkParam = ChunkParam
  { blockSize :: Int
  , blockNum  :: Int
  }

chunkParam :: ChunkParam
chunkParam = ChunkParam
  { blockSize = 16
  , blockNum = 8
  }

data WorldData = WorldData
  { chunkList :: IORef [(ChunkNo,Chunk)]
  }

data Chunk = Chunk
  { origin :: (Int,Int)
  , local :: [(BlockNo,IOArray Int BlockID)]
  , sunLight :: IOUArray Int Int
  }

-- | 

calcCursorPos :: WorldData -> SurfaceList -> UserStatus
              -> IO (Maybe (WorldIndex,Surface))
calcCursorPos wld sufList usr = do
  chl <- readIORef chlist
  f' <- readIORef sufList
  case getChunk chl ( round' ux , round' uy , round' uz) of
    Just (_,c) -> do
      let !(bx,bz) = origin c
          !cblkNo = div (round' uy) blkSize
          !bplst | cblkNo == 0 = [cblkNo, cblkNo + 1]
                 | cblkNo > blkNum - 2 = [cblkNo - 1, cblkNo]
                 | otherwise = [cblkNo - 1, cblkNo, cblkNo + 1]
          !clst = nub $ map fst $ mapMaybe (getChunk chl)
                [(bx + x, 0, bz + z) | x <-[-16,0,16], z <- [-16,0,16]]
          !slst = map (\ c' -> fromJust $ lookup c' f') clst
      f <- mapM (\ (_,b) -> readIORef b)
            $ concatMap (\ s -> map (s !!) bplst) slst 
      let !f'' = filter chkArea (concat f)
          !res = filter chkJustAndFront 
            $ map (tomasChk pos rot . (\ (a,_,b) -> (a,b))) f''
          format =(\ (p,(_,s)) -> (p,s))
                     $ minimumBy (comparing (\ (_,(t,_)) -> t))  $ 
                          map (\ (p,a) -> (p,fromJust a)) res
      --Dbg.traceIO (show (length f''))
      --Dbg.traceIO (show ({-(ux,uy,uz),cblkNo,cNo,clst,bplst-}res)) 
      return $ if null res
             then Nothing
             else Just format
    Nothing -> return Nothing
  where
    chkArea ((sx,sy,sz),_,_) = sqrt ( (fromIntegral sx - ux) ^ (2::Int)
                                  + (fromIntegral sy - uy) ^ (2::Int)
                                  + (fromIntegral sz - uz) ^ (2::Int)) < 8
    chkJustAndFront (_,v) = case v of
                              Just (d,_) -> d > 0
                              Nothing -> False
    blkSize = blockSize chunkParam
    blkNum = blockNum chunkParam
    chlist = chunkList wld
    (ux,uy,uz) = userPos usr
    rot = (\ (a,b,c) -> (realToFrac a, realToFrac b, realToFrac c)) $ userRot usr
    pos = (\ (a,b,c) -> (realToFrac a, realToFrac b + 1.5, realToFrac c)) $ userPos usr

tomasChk :: Pos' -> Rot' -> (WorldIndex,[(Surface,Bright)])
         -> (WorldIndex,Maybe (Double,Surface)) 
tomasChk pos@(px,py,pz) rot (ep,fs) = (ep, choise faceList)
  where
    fs' = map fst fs
    dir =(\ (x,y,z) -> (x - px, y - py, z - pz))
          $ calcPointer pos rot 1
    choise lst = if null lst 
                   then Nothing
                   else Just $ (\ (Just a,s) -> (a,s))
                                     (minimum $ map swap lst)
    faceList = filter (\ (_,v) -> isJust v) $ zip fs' $
                    map (chk . genNodeList (i2d ep)) fs'
    chk ftri = if null l then Nothing else minimum l
      where !l = filter isJust $ map (\ (n1,n2,n3) ->
                           tomasMollerRaw pos dir n1 n2 n3) ftri
    genNodeList pos' face = genTri $ map ((pos' .+. )
      . (\ ((a,b,c),_) -> (realToFrac a, realToFrac b, realToFrac c)))
      $ getVertexList Cube face
    genTri [a1,a2,a3,a4] = [(a1,a2,a3),(a3,a4,a1)]
    i2d (a,b,c) = (fromIntegral a, fromIntegral b, fromIntegral c)

calcPointer :: (Num a,Floating a) => (a,a,a) -> (a,a,a) -> a
            -> (a,a,a)
calcPointer (x,y,z) (rx,ry,_) r =
  ( x + r * ( -sin (d2r ry) * cos (d2r rx))
  , y + r * sin (d2r rx)
  , z + r * cos (d2r (ry + 180)) * cos (d2r rx))
  where
    d2r d = pi*d/180.0


genSurfaceList :: WorldData -> IO SurfaceList
genSurfaceList wld = readIORef chl
  >>= mapM (\ (cNo,_) -> do
    spos <- forM [0 .. bkNo] (\ b -> do
      fs' <- getSurface wld (cNo,b)
      fs <- newIORef fs'
      return (b,fs)) 
    return (cNo,spos)) 
      >>= newIORef
  where
    chl = chunkList wld 
    bkNo = blockNum chunkParam - 1

setSurfaceList :: SurfaceList -> (Int,Int) -> SurfacePos -> IO ()
setSurfaceList sufList (cNo,bNo) sfs = do
  s <- readIORef sufList
  let b = fromJust $ lookup bNo $ fromJust $ lookup cNo s 
  writeIORef b sfs 
  return ()

getSurface :: WorldData -> (ChunkNo,Int) 
           -> IO SurfacePos 
getSurface wld (chNo,bkNo) = do
  blkpos <- getCompliePosList wld (chNo,bkNo)
  blks <- filter (\ (_,bid) -> bid /= AirBlockID ) . zip blkpos
          <$> mapM (getBlockID wld) blkpos
  blks' <- forM blks (\ (pos,bid) -> do
    fs <- catMaybes <$> getSuf pos 
    return (pos,bid,fs)) 
  return $! filter (\ (_,_,fs) -> not $ null fs) blks'
  where
    getAroundIndex (x',y',z') = [ (SRight,(x' + 1, y', z'))
                                , (SLeft, (x' - 1, y', z'))
                                , (STop, (x', y' + 1, z'))
                                , (SBottom, (x', y' - 1, z'))
                                , (SBack,(x', y', z' + 1))
                                , (SFront,(x', y', z' - 1))
                                ]
    getSuf (x',y',z') = forM (getAroundIndex (x',y',z'))
      $ \ (f,pos) -> do
        b <- getBlockID wld pos
        sun <- getSunLightEffect wld pos 
        return $! if b == AirBlockID || alpha (getBlockInfo b) 
           then Just (f,if sun then 16 else 5) 
           else Nothing 


getCompliePosList :: WorldData -> (ChunkNo,Int) -> IO [WorldIndex]
getCompliePosList wld (chNo,blkNo) = do
  chunk <- fmap (fromJust . (lookup chNo)) (readIORef $ chunkList wld)
  let !(x',z') = origin chunk 
      !y' = blkNo * bsize
      (sx,sy,sz) = (f x', f y', f z')
  return [(x,y,z) | x <- [sx .. sx + bsize - 1]
                  , y <- [sy .. sy + bsize - 1]
                  , z <- [sz .. sz + bsize - 1]]
  where
    bsize = blockSize chunkParam
    f a = bsize * (div a bsize)
 

{-
getSuface :: SurfaceList -> (ChunkNo,Int) -> IO (Maybe SurfacePos)
getSuface suf (chNo,bNo) = do
  suf' <- readIORef suf
  case lookup chNo suf' of
    Just chl -> case lookup bNo chl of
      Just blk -> readIORef blk >>= return . Just
      Nothing -> return Nothing
    Nothing -> return Nothing
-}

genWorldData :: IO WorldData
genWorldData = do
  cl <- newIORef . zip [0 ..]
    =<< mapM (\ lst -> do
            c <- genChunk lst
            initSunLight c
            return c)
          [ (x,z) | x <- [-16,0 .. 16], z <- [-16,0 .. 16] ]
        --  [ (x,z) | x <- [-32,-16 .. 32], z <- [-32,-16 .. 32] ]
        --  [ (x,z) | x <- [-64,-48 .. 48], z <- [-64,-48 .. 48] ]
  return WorldData 
    { chunkList =  cl
    }

setBlockID :: WorldData -> WorldIndex -> BlockID
           -> IO ()
setBlockID wld (x,y,z) bid = do
  chl <- readIORef (chunkList wld)
  case getChunk chl (x,y,z) of
    Just (_,c) -> do
      setBlockIDfromChunk c (x,y,z) bid
      let (ox,oz) = origin c
      calcSunLight c (x - ox,z - oz)
    Nothing -> return () 

setBlockIDfromChunk :: Chunk -> WorldIndex -> BlockID -> IO ()
setBlockIDfromChunk c (x,y,z) = writeArray arr idx 
  where
    bsize = blockSize chunkParam
    (lx,ly,lz) = (x - ox, y - bsize * div y bsize, z - oz )
    (ox,oz) = origin c
    dat = local c
    arr = fromJust $ lookup (div y bsize) dat
    idx = (bsize ^ (2::Int)) * ly + bsize * lz + lx

getBlockID :: WorldData -> WorldIndex -> IO BlockID
getBlockID wld (x,y,z) = do
  chl <- readIORef chlist
  case getChunk chl (x,y,z) of
    Just (_,c) -> getBlockIDfromChunk c (x,y,z)
    Nothing -> return OutOfRange
  where
    chlist = chunkList wld

getBlockIDfromChunk :: Chunk -> WorldIndex -> IO BlockID
getBlockIDfromChunk c (x,y,z) = readArray arr idx
  where
    bsize = blockSize chunkParam
    (lx,ly,lz) = (x - ox, y - (div y bsize) * bsize, z - oz)
    (ox,oz) = origin c
    dat = local c
    arr = fromJust $ lookup (div y bsize) dat
    idx = (bsize * bsize) * ly + bsize * lz + lx

calcReGenArea :: WorldData -> WorldIndex -> IO [(ChunkNo,BlockNo)]
calcReGenArea wld (x,y,z) = do
  chl <- readIORef chlist
  case getChunk chl (x,y,z) of
    Nothing -> return [] 
    Just (cNo,_) -> return $
         map (\ bno' -> (cNo,bno')) blknos 
      ++ map (\ cno' -> (cno',bNo)) (cNoX chl)
      ++ map (\ cno' -> (cno',bNo)) (cNoZ chl)
  where
    bsize = blockSize chunkParam
    blkNum = blockNum chunkParam
    chlist = chunkList wld
    bNo = div y bsize
    blknos | mod y bsize == 0 && bNo > 0 = [bNo,bNo - 1]
           | mod y bsize == bsize - 1 && bNo < blkNum - 1 = [bNo,bNo + 1]
           | otherwise = [bNo]
    cNoX chl | mod x bsize == 0 = case getChunk chl (x - 1,y,z) of
                                   Nothing -> [] 
                                   Just (cNo,_) -> [cNo]
             | mod x bsize == bsize - 1 = case getChunk chl (x + 1,y,z) of
                                   Nothing -> [] 
                                   Just (cNo,_) -> [cNo]
             | otherwise = []
    cNoZ chl | mod z bsize == 0 = case getChunk chl (x,y,z - 1) of
                                   Nothing -> [] 
                                   Just (cNo,_) -> [cNo]
             | mod z bsize == bsize - 1 = case getChunk chl (x,y,z + 1) of
                                   Nothing -> [] 
                                   Just (cNo,_) -> [cNo]
             | otherwise = []

genChunk :: (Int,Int) -> IO Chunk
genChunk org = do
  arrt <- replicateM 4
    (newArray (0, blength) AirBlockID) :: IO [IOArray Int BlockID]

  arrs <- newArray (0,blength) AirBlockID :: IO (IOArray Int BlockID)
  mapM_ (\ i -> writeArray arrs i DirtBlockID) [0 .. 16 * 16 * 2 - 1]
  mapM_ (\ i -> writeArray arrs i GrassBlockID)
           [ 16 * 16 * 2 .. 16 * 16 * 3 - 1]

  arrb <- replicateM 3
    (newArray (0,blength) StoneBlockID) :: IO [IOArray Int BlockID]

  sun' <- newArray (0, (blockSize chunkParam ^ (2::Int)) - 1) 0

  return Chunk
    { origin = org
    , local = zip [0 .. ] $ arrb ++ (arrs : arrt)
    , sunLight = sun'
    } 
  where
    blength = (blockSize chunkParam ^ (3::Int)) -1

getChunk :: [(ChunkNo,Chunk)] -> WorldIndex -> Maybe (ChunkNo,Chunk)
getChunk [] _ = Nothing 
getChunk (c:cs) (x,y,z) | (ox <= x) && (x < ox + bsize) &&
                          (oz <= z) && (z < oz + bsize) &&
                          (ymin <= y) && (y < ymax )
                           = Just c  
                        | otherwise = getChunk cs (x,y,z)
  where
    (ox,oz) = origin $ snd c
    (ymin,ymax) = (0,blockSize chunkParam * blockNum chunkParam)
    bsize = blockSize chunkParam



initSunLight :: Chunk -> IO ()
initSunLight chunk = mapM_ (calcSunLight chunk) 
      [(x,z) | x <- lst, z <- lst]
  where
    lst = [0 .. blockSize chunkParam - 1]

calcSunLight :: Chunk -> (Int,Int) -> IO ()
calcSunLight chunk pos =
  chk pos blks initY
    >>= writeArray (sunLight chunk) (calcIdx pos)
  where 
    blks = reverse $ local chunk
    initY = blockNum chunkParam * blockSize chunkParam - 1
    calcIdx (x,z) = z * blockSize chunkParam + x
    chk _ [] y = return y
    chk (x,z) (b:bs) y = do
      v <- chk' (snd b) (calcIdx (x,z)) $ blockSize chunkParam - 1
      if v < 0
        then chk (x,z) bs (y - blockSize chunkParam)
        else return (y - blockSize chunkParam + v + 1)
                                              -- +1 して Indexを数へ変換
    layerSize = blockSize chunkParam ^ (2::Int)
    chk' :: IOArray Int BlockID -> Int -> Int -> IO Int
    chk' blk offset count
      | count < 0 = return (-1)
      | otherwise = do
          v <- readArray blk $ count * layerSize + offset
          if v == AirBlockID || alpha (getBlockInfo v)
            then chk' blk offset (count - 1)
            else return (count + 1) -- 一つ前のIndexへ戻す

getSunLightEffect :: WorldData -> WorldIndex -> IO Bool
getSunLightEffect wld pos@(x,y,z) = do
  chl <- readIORef chlist
  case getChunk chl pos of
    Just (_,cnk) -> do
      let (ox,oz) = origin cnk
      readArray (sunLight cnk) (calcIdx (x - ox,z - oz))
        >>= return . (y >=)  
    Nothing -> return False
  where
    chlist = chunkList wld
    calcIdx (x',z') = z' * (blockSize chunkParam) + x'


