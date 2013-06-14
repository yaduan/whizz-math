///
//  ProgressTimer.m
//
//  Created by Lam Pham on 23/10/09.
///

#import "CCProgressTime.h"

#import "ccMacros.h"
#import "CCTextureCache.h"
#import "CGPointExtension+More.h"
#import "CCTypes+More.h"


#define kProgressTextureCoordsCount 4
//  kProgressTextureCoords holds points {0,0} {0,1} {1,1} {1,0} we can represent it as bits
const char kProgressTextureCoords = 0x1e;

@interface CCProgressTime (Internal)

-(void)updateProgress;
-(void)updateBar;
-(void)updateRadial;
-(void)updateColor;
-(CGPoint)boundaryTexCoord:(char)index;
@end


@implementation CCProgressTime
@synthesize percentage = percentage_;
@synthesize sprite = sprite_;
@synthesize type = type_;

+(id)progressWithFile:(NSString*) filename
{
	return [[[self alloc]initWithFile:filename] autorelease];
}
-(id)initWithFile:(NSString*) filename
{
	return [self initWithTexture:[[CCTextureCache sharedTextureCache] addImage: filename]];
}

+(id)progressWithTexture:(CCTexture2D*) texture
{
	return [[[self alloc]initWithTexture:texture] autorelease];
}
-(id)initWithTexture:(CCTexture2D*) texture
{
	if(( self = [super init] )){
		self.sprite = [CCSprite spriteWithTexture:texture];
		percentage_ = 0.f;
		vertexData_ = NULL;
		vertexDataCount_ = 0;
		self.anchorPoint = ccp(.5f,.5f);
		self.contentSize = sprite_.contentSize;
		self.type = kProgressTimerTypeRadialCCW;
	}
	return self;
}
-(void)dealloc
{
	if(vertexData_){
		free(vertexData_);
	}
	[sprite_ release];
	[super dealloc];
}

-(void)setPercentage:(float) percentage
{
	if(percentage_ != percentage){
		if(percentage_ < 0.f)
			percentage_ = 0.f;
		else if(percentage > 100.0f)
			percentage_  = 100.f;
		else
			percentage_ = percentage;
		
		[self updateProgress];
	}
}
-(void)setSprite:(CCSprite *)newSprite
{
	if(sprite_ != newSprite){
		[sprite_ release]; 
		sprite_ = [newSprite retain];
		
		//	Everytime we set a new sprite, we free the current vertex data
		if(vertexData_){
			free(vertexData_);
			vertexData_ = NULL;
			vertexDataCount_ = 0;
		}
	}
}
-(void)setType:(CCProgressTimerType)newType
{
	if (newType != type_) {
		
		//	release all previous information
		if(vertexData_){
			free(vertexData_);
			vertexData_ = NULL;
			vertexDataCount_ = 0;
		}
		type_ = newType;
	}
}
@end

@implementation CCProgressTime(Internal)

///
//	@returns the vertex position from the texture coordinate
///
-(CGPoint)vertexFromTexCoord:(CGPoint) texCoord
{
	if (sprite_.texture) {
		return ccp(sprite_.texture.contentSize.width * texCoord.x/sprite_.texture.maxS,
				   sprite_.texture.contentSize.height * (1 - (texCoord.y/sprite_.texture.maxT)));
	} else {
		return CGPointZero;
	}
}
-(void)updateColor {
	ccColor4F color = ccc4FFromccc3B(sprite_.color);
	if([sprite_.texture hasPremultipliedAlpha]){
		float op = sprite_.opacity/255.f;
		color.r *= op;
		color.g *= op;
		color.b *= op;
		color.a = op;
	} else {
		color.a = sprite_.opacity/255.f;
	}
	
	if(vertexData_){
		for (int i=0; i < vertexDataCount_; ++i) {
			vertexData_[i].colors = color;
		}
	}
}

-(void)updateProgress
{
	switch (type_) {
		case kProgressTimerTypeRadialCW:
		case kProgressTimerTypeRadialCCW:
			[self updateRadial];
			break;
		case kProgressTimerTypeHorizontalBarLR:
		case kProgressTimerTypeHorizontalBarRL:
		case kProgressTimerTypeVerticalBarBT:
		case kProgressTimerTypeVerticalBarTB:
			[self updateBar];
			break;
		default:
			break;
	}
}

///
//	Update does the work of mapping the texture onto the triangles
//	It now doesn't occur the cost of free/alloc data every update cycle.
//	It also only changes the percentage point but no other points if they have not
//	been modified.
//	
//	It now deals with flipped texture. If you run into this problem, just use the
//	sprite property and enable the methods flipX, flipY.
///
-(void)updateRadial
{		
	//	Texture Max is the actual max coordinates to deal with non-power of 2 textures
	CGPoint tMax = ccp(sprite_.texture.maxS,sprite_.texture.maxT);
	
	//	Grab the midpoint
	CGPoint midpoint = ccpCompMult(self.anchorPoint, tMax);
	
	float alpha = percentage_ / 100.f;
	
	//	Otherwise we can get the angle from the alpha
	float angle = 2.f*M_PI * ( type_ == kProgressTimerTypeRadialCW? alpha : 1.f - alpha);
	
	//	We find the vector to do a hit detection based on the percentage
	//	We know the first vector is the one @ 12 o'clock (top,mid) so we rotate 
	//	from that by the progress angle around the midpoint pivot
	CGPoint topMid = ccp(midpoint.x, 0.f);
	CGPoint percentagePt = ccpRotateByAngle(topMid, midpoint, angle);
	
/*	CGPoint hit = topMid;
	
	//	If we've previosly had vertexData then we can help find the intersection faster
	//	with this hint.
	int index = vertexDataCount_ > 3? vertexDataCount_ - 3 : 0;*/
	int index = 0;
	float min_t = FLT_MAX;
	
	if (alpha == 0.f) {
		//	More efficient since we don't always need to check intersection
		//	If the alpha is zero then the hit point is top mid and the index is 0.
		index = 0;
	} else if (alpha == 1.f) {
		//	More efficient since we don't always need to check intersection
		//	If the alpha is one then the hit point is top mid and the index is 4.
		index = 4;
	} else {
		//	We run a for loop checking the edges of the texture to find the
		//	intersection point
		//	We loop through five points since the top is split in half
		for (int i = 0; i <= kProgressTextureCoordsCount; ++i) {
			int pIndex = (i + (kProgressTextureCoordsCount - 1))%kProgressTextureCoordsCount;
			
			CGPoint edgePtA = ccpCompMult([self boundaryTexCoord:i % kProgressTextureCoordsCount],tMax);
			CGPoint edgePtB = ccpCompMult([self boundaryTexCoord:pIndex],tMax);
			//	Remember that the top edge is split in half for the 12 o'clock position
		//	Let's deal with that here by finding the correct endpoints
					
			if(i == 0){
				edgePtB = ccpLerp(edgePtA,edgePtB,.5f);
			} else if(i == 4){
				edgePtA = ccpLerp(edgePtA,edgePtB,.5f);
			}
			
			//	s and t are returned by ccpLineIntersect
			float s = 0, t = 0;
			if(ccpLineIntersect(edgePtA, edgePtB, midpoint, percentagePt, &s, &t))
			{	
				
				if ((i == 0 || i == 4)) {
					
					if (!(0.f <= s && s <= 1.f)) {
						continue;
					}
				}
				//	As long as our t isn't negative we are at least finding a
				//	correct hitpoint from midpoint to percentagePt.
				if (t >= 0.f) {
					//	Because the percentage line and all the texture edges are
					//	rays we should only account for the shortest intersection
					if (t < min_t) {
						min_t = t;
						index = i;
					}
				}
			}
		}
	}
	//	Now that we have the minimum magnitude we can use that to find our intersection
	CGPoint hit = ccpAdd(midpoint, ccpMult(ccpSub(percentagePt, midpoint),min_t));
	//	The size of the vertex data is the index from the hitpoint
	//	the 3 is for the midpoint, 12 o'clock point and hitpoint position.
	
	BOOL sameIndexCount = YES;
	if(vertexDataCount_ != index + 3){
		sameIndexCount = NO;
		if(vertexData_){
			free(vertexData_);
			vertexData_ = NULL;
			vertexDataCount_ = 0;
		}
	}
	
	
	if(!vertexData_) {
		vertexDataCount_ = index + 3;
		vertexData_ = malloc(vertexDataCount_ * sizeof(ccV2F_C4F_T2F));
		[self updateColor];
	}
	
	if (!sameIndexCount) {
		
		//	First we populate the array with the midpoint, then all 
		//	vertices/texcoords/colors of the 12 'o clock start and edges and the hitpoint
		vertexData_[0].texCoords = (ccTex2F){midpoint.x, midpoint.y};
		vertexData_[0].vertices = [self vertexFromTexCoord:midpoint];
		
		vertexData_[1].texCoords = (ccTex2F){midpoint.x, 0.f};
		vertexData_[1].vertices = [self vertexFromTexCoord:ccp(midpoint.x, 0.f)];
		
		for(int i = 0; i < index; ++i){
			CGPoint texCoords = ccpCompMult([self boundaryTexCoord:i], tMax);
			
			vertexData_[i+2].texCoords = (ccTex2F){texCoords.x, texCoords.y};
			vertexData_[i+2].vertices = [self vertexFromTexCoord:texCoords];
		}
		
		//	Flip the texture coordinates if set
		if (sprite_.flipY || sprite_.flipX) {
			for(int i = 0; i < vertexDataCount_ - 1; ++i){
				if (sprite_.flipX) {
					vertexData_[i].texCoords.u = tMax.x - vertexData_[i].texCoords.u;
				}
				if(sprite_.flipY){
					vertexData_[i].texCoords.v = tMax.y - vertexData_[i].texCoords.v;
				}
			}
		}
	}
	
	//	hitpoint will go last
	vertexData_[vertexDataCount_ - 1].texCoords = (ccTex2F){hit.x, hit.y};
	vertexData_[vertexDataCount_ - 1].vertices = [self vertexFromTexCoord:hit];
	
	if (sprite_.flipY || sprite_.flipX) {
		if (sprite_.flipX) {
			vertexData_[vertexDataCount_ - 1].texCoords.u = tMax.x - vertexData_[vertexDataCount_ - 1].texCoords.u;
		}
		if(sprite_.flipY){
			vertexData_[vertexDataCount_ - 1].texCoords.v = tMax.y - vertexData_[vertexDataCount_ - 1].texCoords.v;
		}
	}
}

///
//	Update does the work of mapping the texture onto the triangles for the bar
//	It now doesn't occur the cost of free/alloc data every update cycle.
//	It also only changes the percentage point but no other points if they have not
//	been modified.
//	
//	It now deals with flipped texture. If you run into this problem, just use the
//	sprite property and enable the methods flipX, flipY.
///
-(void)updateBar
{	
	
	float alpha = percentage_ / 100.f;
	
	CGPoint tMax = ccp(sprite_.texture.maxS,sprite_.texture.maxT);
	
	unsigned char vIndexes[2] = {0,0};
	
	//	We know vertex data is always equal to the 4 corners
	//	If we don't have vertex data then we create it here and populate
	//	the side of the bar vertices that won't ever change.
	if (!vertexData_) {
		vertexDataCount_ = kProgressTextureCoordsCount;
		vertexData_ = malloc(vertexDataCount_ * sizeof(ccV2F_C4F_T2F));
		
		if(type_ == kProgressTimerTypeHorizontalBarLR){
			vertexData_[vIndexes[0] = 0].texCoords = (ccTex2F){0,0};
			vertexData_[vIndexes[1] = 1].texCoords = (ccTex2F){0, tMax.y};
		}else if (type_ == kProgressTimerTypeHorizontalBarRL) {
			vertexData_[vIndexes[0] = 2].texCoords = (ccTex2F){tMax.x, tMax.y};
			vertexData_[vIndexes[1] = 3].texCoords = (ccTex2F){tMax.x, 0.f};
		}else if (type_ == kProgressTimerTypeVerticalBarBT) {
			vertexData_[vIndexes[0] = 1].texCoords = (ccTex2F){0, tMax.y};
			vertexData_[vIndexes[1] = 3].texCoords = (ccTex2F){tMax.x, tMax.y};
		}else if (type_ == kProgressTimerTypeVerticalBarTB) {
			vertexData_[vIndexes[0] = 0].texCoords = (ccTex2F){0, 0};
			vertexData_[vIndexes[1] = 2].texCoords = (ccTex2F){tMax.x, 0};
		}
		
		unsigned char index = vIndexes[0];
		vertexData_[index].vertices =[self vertexFromTexCoord:ccp(vertexData_[index].texCoords.u, vertexData_[index].texCoords.v)];
		
		index = vIndexes[1];
		vertexData_[index].vertices = [self vertexFromTexCoord:ccp(vertexData_[index].texCoords.u, vertexData_[index].texCoords.v)];
		
		if (sprite_.flipY || sprite_.flipX) {
			if (sprite_.flipX) {
				unsigned char index = vIndexes[0];
				vertexData_[index].texCoords.u = tMax.x - vertexData_[index].texCoords.u;
				index = vIndexes[1];
				vertexData_[index].texCoords.u = tMax.x - vertexData_[index].texCoords.u;
			}
			if(sprite_.flipY){
				unsigned char index = vIndexes[0];
				vertexData_[index].texCoords.v = tMax.y - vertexData_[index].texCoords.v;
				index = vIndexes[1];
				vertexData_[index].texCoords.v = tMax.y - vertexData_[index].texCoords.v;
			}
		}
		
		[self updateColor];
	}
	
	if(type_ == kProgressTimerTypeHorizontalBarLR){
		vertexData_[vIndexes[0] = 3].texCoords = (ccTex2F){tMax.x*alpha, tMax.y};
		vertexData_[vIndexes[1] = 2].texCoords = (ccTex2F){tMax.x*alpha, 0};
	}else if (type_ == kProgressTimerTypeHorizontalBarRL) {
		vertexData_[vIndexes[0] = 1].texCoords = (ccTex2F){tMax.x*(1.f - alpha), 0};
		vertexData_[vIndexes[1] = 0].texCoords = (ccTex2F){tMax.x*(1.f - alpha), tMax.y};
	}else if (type_ == kProgressTimerTypeVerticalBarBT) {
		vertexData_[vIndexes[0] = 0].texCoords = (ccTex2F){0, tMax.y*(1.f - alpha)};
		vertexData_[vIndexes[1] = 2].texCoords = (ccTex2F){tMax.x, tMax.y*(1.f - alpha)};
	}else if (type_ == kProgressTimerTypeVerticalBarTB) {
		vertexData_[vIndexes[0] = 1].texCoords = (ccTex2F){0, tMax.y*alpha};
		vertexData_[vIndexes[1] = 3].texCoords = (ccTex2F){tMax.x, tMax.y*alpha};
	}
	
	unsigned char index = vIndexes[0];
	vertexData_[index].vertices = [self vertexFromTexCoord:ccp(vertexData_[index].texCoords.u, vertexData_[index].texCoords.v)];
	index = vIndexes[1];
	vertexData_[index].vertices = [self vertexFromTexCoord:ccp(vertexData_[index].texCoords.u, vertexData_[index].texCoords.v)];
	
	if (sprite_.flipY || sprite_.flipX) {
		if (sprite_.flipX) {
			unsigned char index = vIndexes[0];
			vertexData_[index].texCoords.u = tMax.x - vertexData_[index].texCoords.u;
			index = vIndexes[1];
			vertexData_[index].texCoords.u = tMax.x - vertexData_[index].texCoords.u;
		}
		if(sprite_.flipY){
			unsigned char index = vIndexes[0];
			vertexData_[index].texCoords.v = tMax.y - vertexData_[index].texCoords.v;
			index = vIndexes[1];
			vertexData_[index].texCoords.v = tMax.y - vertexData_[index].texCoords.v;
		}
	}
	
}

-(CGPoint)boundaryTexCoord:(char)index
{
	if (index < kProgressTextureCoordsCount) {
		switch (type_) {
			case kProgressTimerTypeRadialCW:
				return ccp((kProgressTextureCoords>>((index<<1)+1))&1,(kProgressTextureCoords>>(index<<1))&1);
			case kProgressTimerTypeRadialCCW:
				return ccp((kProgressTextureCoords>>(7-(index<<1)))&1,(kProgressTextureCoords>>(7-((index<<1)+1)))&1);
			default:
				break;
		}
	}
	return CGPointZero;
}

-(void)draw {
	if(!vertexData_)return;
	if(!sprite_)return;
	BOOL newBlend = NO;
	if( sprite_.blendFunc.src != CC_BLEND_SRC || sprite_.blendFunc.dst != CC_BLEND_DST ) {
		newBlend = YES;
		glBlendFunc( sprite_.blendFunc.src, sprite_.blendFunc.dst );
	}
	
	///	========================================================================
	//	Replaced [texture_ drawAtPoint:CGPointZero] with my own vertexData
	//	Everything above me and below me is copied from CCTextureNode's draw
	glBindTexture(GL_TEXTURE_2D, sprite_.texture.name);
	glVertexPointer(2, GL_FLOAT, sizeof(ccV2F_C4F_T2F), &vertexData_[0].vertices);
	glTexCoordPointer(2, GL_FLOAT, sizeof(ccV2F_C4F_T2F), &vertexData_[0].texCoords);
	glColorPointer(4, GL_FLOAT, sizeof(ccV2F_C4F_T2F), &vertexData_[0].colors);
	if(type_ == kProgressTimerTypeRadialCCW || type_ == kProgressTimerTypeRadialCW){
		glDrawArrays(GL_TRIANGLE_FAN, 0, vertexDataCount_);
	} else if (type_ == kProgressTimerTypeHorizontalBarLR ||
			   type_ == kProgressTimerTypeHorizontalBarRL ||
			   type_ == kProgressTimerTypeVerticalBarBT ||
			   type_ == kProgressTimerTypeVerticalBarTB) {
		glDrawArrays(GL_TRIANGLE_STRIP, 0, vertexDataCount_);
	}
	//glDrawElements(GL_TRIANGLES, indicesCount_, GL_UNSIGNED_BYTE, indices_);
	///	========================================================================
	
	if( newBlend )
		glBlendFunc(CC_BLEND_SRC, CC_BLEND_DST);
}

@end
