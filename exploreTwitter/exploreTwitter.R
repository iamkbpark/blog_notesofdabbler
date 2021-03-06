#' # Explore #Mangalyaan tweets in Twitter with R
#' 
#' I wanted to use R to explore the tweets with hashtag #Mangalyaan. When Mangalyaan has launched, [Tiger Analytics](http://www.tigeranalytics.com/blogs/20131221/text-analytics-%E2%80%98mangalyaan%E2%80%99-seen-twitter) had done a nice blog post on analyzing twitter data containing #Mangalyaan (I hope they redo their analysis with the latest tweets). That analysis was very interesting especially where they mention using hierarchical bayes to get topics of the tweets. My attempt here is much more basic. My goal here is the following:
#' 
#' * Extract tweets with hashtag #Mangalyaan
#' * Get some sense for themes using the following 3 methods:
#'   + topics with package topicmodels
#'   + Hierarchical cluster analysis
#'   + Community detection algorithms on graphs
#'   
#' I had borrowed from several sources in the web. The key sites from which I borrowed/adapted code for this post are:
## ------------------------------------------------------------------------
# http://davetang.org/muse/2013/04/06/using-the-r_twitter-package/
# http://www.rdatamining.com/examples/text-mining
# http://thinktostart.com/create-twitter-sentiment-word-cloud-in-r/
# http://heuristically.wordpress.com/2011/04/08/text-data-mining-twitter-r/

#'   
#' ## Extract Data from Twitter  
#' 
## ------------------------------------------------------------------------
## Set up - load libraries and set working directory

# load libraries
library(twitteR)
library(tm)
library(wordcloud)
library(dplyr)
library(topicmodels)
library(RColorBrewer)
library(igraph)

# set working directory
setwd("~/notesofdabbler/githubfolder/blog_notesofdabbler/exploreTwitter/")

## Set up to access Twitter

#necessary step for Windows
download.file(url="http://curl.haxx.se/ca/cacert.pem", destfile="cacert.pem")

# Set SSL certs globally
options(RCurlOptions = list(cainfo = system.file("CurlSSL", "cacert.pem", package = "RCurl")))

# Here I have stored the Twitter keys (consumerKey and ConsumerSecret) in a file keys.R. It has the following code
# cousumerKey=myKey
# consumerSecret=mySecret
#
# Check instructions in twitteR package documentation to get consumerKey and consumerSecret
#
source("keys.R")

cred <- OAuthFactory$new(consumerKey=myKey,
                         consumerSecret=mySecret,
                         requestURL='https://api.twitter.com/oauth/request_token',
                         accessURL='https://api.twitter.com/oauth/access_token',
                         authURL='https://api.twitter.com/oauth/authorize')

#necessary step for Windows
# Running this line will prompt you go go to a URL and get the PIN and paste it back in the R console
cred$handshake()
#save for later use for Windows
save(cred, file="twitterAuthentication.Rdata")
# if running this line is TRUE, then all is good to go
registerTwitterOAuth(cred)

# 
# ### Get data for a hashtag from Twitter
# I used the code below to get data for the hashtag of interest. I am still a bit confused about rate limit errors. I sometimes got some rate limit errors and therefore ran the code below separately for four periods from 2014-09-23 to 2014-09-26 and saved them to separate data sets. A caveat of this analysis is that the tweets used for analysis are only a small sample of all the tweets.

# get tweets with a hashtag
getTw <- searchTwitter("#Mangalyaan",n=1500,since="2014-09-26",until="2014-09-27",cainfo="cacert.pem")

# get text of each tweet
getTw_txt <- sapply(getTw, function(x) x$getText())
# get info on whether the tweet is a retweet
getTw_rt <- sapply(getTw,function(x) x$getIsRetweet())
# get the date tweet was created
getTw_dt <- do.call(c,lapply(getTw,function(x) x$created))
getTw_dt <- as.Date(getTw_dt,format="%Y%m%d")
# combine tweet info into a data frame
getTw_df <- data.frame(date=getTw_dt,txt=getTw_txt,rt=getTw_rt)
table(getTw_df$date)

# save data
save(getTw_df,file="getTw_df_20140926.Rda")

#' 
#' ## Analyze Data
#' 
#' ### Load and clean data
#' 
## ------------------------------------------------------------------------
# load tweets for 2014-09-23
load(file="getTw_df_20140923.Rda")
getTw_df_0923 <- getTw_df
# load tweets for 2014-09-24
load(file="getTw_df_20140924.Rda")
getTw_df_0924 <- getTw_df
# load tweets for 2014-09-25
load(file="getTw_df_20140925.Rda")
getTw_df_0925 <- getTw_df
# load tweets for 2014-09-26
load(file="getTw_df_20140926.Rda")
getTw_df_0926 <- getTw_df

# combine into a single data frame
getTw_df <- rbind(getTw_df_0923,getTw_df_0924,getTw_df_0925,getTw_df_0926)
getTw_df$txt <- as.character(getTw_df$txt)

# check number of tweets in the dataset by day
table(getTw_df$date)

# Remove duplicate tweets (could occur due to several retweets of a tweet)
getTw_df_rmRT <- getTw_df%>%filter(!duplicated(txt))


# remove non alphanumeric characters
getTw_txt_cln <- gsub("[^a-zA-Z0-9 ]","",getTw_df_rmRT$txt)
# remove words starting with @
getTw_txt_cln <- gsub("@\\w+","",getTw_txt_cln)
# remove word amp
getTw_txt_cln <- gsub("amp","",getTw_txt_cln)
# remove words containing http
getTw_txt_cln <- gsub("\\bhttp[a-zA-Z0-9]*\\b","",getTw_txt_cln)
# remove the word RT
getTw_txt_cln <- gsub("\\bRT\\b","",getTw_txt_cln)


head(getTw_txt_cln)

#create corpus
getTw_txt_cln <- Corpus(VectorSource(getTw_txt_cln))
#clean up
getTw_txt_cln <- tm_map(getTw_txt_cln, tolower) 
getTw_txt_cln <- tm_map(getTw_txt_cln, removePunctuation)

# I first ran with just english stopwords and then looked at top words. Then I added those to the stopword list
mystopwords <- c(stopwords('english'),"mangalyaan","marsmission","missionmars","isro","india","mars",
                   "indias","mission")
getTw_txt_cln <- tm_map(getTw_txt_cln, removeWords, mystopwords)
getTw_txt_cln <- tm_map(getTw_txt_cln, PlainTextDocument)

# get the document term matrix
myDTM <- DocumentTermMatrix(getTw_txt_cln)
# get the matrix version of document term matrix
m <- as.matrix(myDTM)

#' ### Wordcloud of words in the tweets
#' 
## ------------------------------------------------------------------------
# find frequency of occurence of each word, put it into a dataframe and sort descending
tfreq <- colSums(m)
tfreqdf <- data.frame(term=names(tfreq),tfreq=tfreq,stringsAsFactors=FALSE)
tfreqdf <- tfreqdf%>%arrange(desc(tfreq))

# check the distribution of word frequency
tfreqdfagg <- tfreqdf%>%group_by(tfreq)%>%summarize(count=n())%>%arrange(desc(tfreq))
tfreqdfagg$cumcount <- cumsum(tfreqdfagg$count)

pal <- brewer.pal(6,"Dark2")
pal <- pal[-(1)]
wordcloud(tfreqdf$term,tfreqdf$tfreq,min.freq=20,random.color=FALSE,colors=pal)

#' 
#' ### Topics with topicmodels package
#' 
#' There is R package [topicmodels](http://cran.r-project.org/web/packages/topicmodels/index.html). There is also a nice [article](http://cran.r-project.org/web/packages/topicmodels/vignettes/topicmodels.pdf) explaining how it works. While any analysis with this requires some good preprocessing of data and trying about models with different values of tuning parameters, I just applied it here with some basic preprocessing and a version of model code taken directly from the [article](http://cran.r-project.org/web/packages/topicmodels/vignettes/topicmodels.pdf).
#' 
## ------------------------------------------------------------------------
# number of topics
k=5
SEED=2010
# filter document term matrix
# keep rows that have at least one term
mfilt <- m[rowSums(m)>0,]
# dimension of document term matrix (#documents x #terms)
dim(mfilt)
# fit LDA model
LDAfit <- LDA(mfilt,k=k,control=list(seed=SEED))

# get top 5 terms of each topic
Terms <- terms(LDAfit,10)
Terms

# get topic probablities for each tweet
pDoc <- posterior(LDAfit)

# find the topic with max probability for a tweet
topicProb <- apply(pDoc[[2]],1,function(x) max(x))
# assign topic as the topic with max probability
topicPick <- apply(pDoc[[2]],1,function(x) which(x==max(x)))
# find distribution of topics among tweets
table(topicPick)

#' I am finding hard to assign clear themes to the topics based on the terms above. But as I mentioned before the model above uses basic preprocessing and LDA model with default options. I think trying to get good themes requires more thinking and effort in both preprocessing and figuring the right tuning parameters for training the LDA model. 
#' 
#' ## Find groups with hierarchical clustering
#' 
#' Here I filtered the document term matrix to words that occur quite frequently and did a hierarchical clustering.
#' 
## ------------------------------------------------------------------------
# Hierarchical Clustering

# choose documents that have at least one term
mfilt <- m[rowSums(m)>0,]
# select terms that occur at least 25 times
mfilt <- mfilt[,colSums(mfilt)>=25]
# create a data frame (rows - terms, columns - documents)
mfiltDf <- as.data.frame(t(mfilt))
dim(mfiltDf)

# do hierarchical clustering
mfiltDfScale <- scale(mfiltDf)
d <- dist(mfiltDfScale,method="euclidean")
fit <- hclust(d,method="ward.D")
png("hierClust.png",width=800,height=500)
plot(fit)

# draw rectangles around clusters by choosing number of clusters
groups <- cutree(fit,k=5)
rect.hclust(fit,k=5,border="red")
dev.off()

#' 
#' ## Find groups using graph community detection
#' 
#' Here I first created the number of co-occurences of a pair of terms and zero out any pairs that occurred less than a certain number of times. Here I chose 8 with some trial error (with the objective of not having too many non-zero pairs)
## ------------------------------------------------------------------------
mfilt2 <- mfilt
mfilt2[mfilt > 0] <- 1
d <- t(mfilt2)%*%mfilt2
d[d<8] <- 0
dim(d)

#' 
#' Next, I used created a undirected graph using the distance matrix above and put edge weights are the number of co-occurence of words. I used the [igraph](http://igraph.org/r/) package.
## ------------------------------------------------------------------------
g <- graph.adjacency(d,weighted=TRUE,mode="undirected",diag=FALSE)
# number of edges in the graph
length(E(g))

#' 
#' There are several community detection algorithms available in igraph package. Here I just used one to see how it groups terms. It also has option to plot it as a graph or as a dendrogram.
## ----,fig.height=8,fig.width=8-------------------------------------------
# community calculation
fc <- edge.betweenness.community(g)
# dendrogram plot
png("communityDendPlot.png",width=600,height=800)
dendPlot(fc)
dev.off()
# graph plot
png("communityGraphPlot.png",width=800,height=800)
plot(fc,g)
dev.off()

#' 
#' ## Session Info
#' 
#' This was done in RStudio 0.98.1062.
#' 
## ------------------------------------------------------------------------
sessionInfo()

