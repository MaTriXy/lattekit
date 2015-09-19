package io.lattekit.ui

import android.R
import android.animation.Animator
import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.Point
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.graphics.drawable.ShapeDrawable
import android.os.Build
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.view.View.MeasureSpec
import android.view.View.OnClickListener
import android.view.View.OnTouchListener
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams
import android.widget.FrameLayout
import android.widget.TextView
import io.lattekit.State
import java.util.List
import java.util.Map
import org.eclipse.xtend.lib.annotations.Accessors

import static io.lattekit.xtend.ArrayLiterals2.*

public abstract class LatteView implements OnTouchListener, OnClickListener {
	
	public final int MATCH_PARENT = LayoutParams.MATCH_PARENT;
	public final int WRAP_CONTENT = LayoutParams.WRAP_CONTENT;
	public final int match_parent = LayoutParams.MATCH_PARENT;
	public final int wrap_content = LayoutParams.WRAP_CONTENT;
	 
	/** Base Attributes */ 
	@Accessors public String id;
	@Accessors public (LatteView)=>void onTap;
	@Accessors public (LatteView, MotionEvent)=>boolean onTouch;
	
	public var Animator currentAnimation;
	public var Style pendingStyle;

	@Accessors public Style normalStyle = new Style();
	@Accessors public Style touchedStyle = new Style() => [ parentStyle = normalStyle ];
	@Accessors public Style disabledStyle = new Style() => [ parentStyle = normalStyle ];
	Style _style = new Style();	
	@State public boolean enabled = true;
	@State public boolean touched = false;
	
		
	// Generic Attributes
	public Map<String,Object> attributes = newHashMap();
	
	@Accessors public LatteView parentView;
	// This contains current active children
	@Accessors public List<LatteView> children = newArrayList;
	@Accessors private List<LatteView> subviews = newArrayList;
	private Map<String,Object> newProperties = newHashMap();
	
	public Activity activity;
	@Accessors View androidView;
	
	public ShapeDrawable shapeDrawable;
	public GradientDrawable backgroundDrawable;
	protected (LatteView)=>void attributesProc;
	protected (LatteView)=>void layoutProc;
	private boolean isRendering = false;
	
	def setStyle(Style style) {
		normalStyle.cloneFrom(style);
		if (_style == null) {
			_style = new Style();
			_style.cloneFrom(normalStyle);
		}		
		onStateChanged("style");	
	}
	def getStyle() {
		return normalStyle;
	}
	
	def void setTouchedStyle(Style style) {
		this.touchedStyle.cloneFrom(style);
		onStateChanged("touchedStyle");	
	}
	
	def void setDisabledStyle(Style style) {
		this.disabledStyle.cloneFrom(style);
		onStateChanged("disabledStyle");	
	}
	
	def getActiveStyle() {
		if (!enabled && disabledStyle != null) {
			return disabledStyle
		} else if (touched && touchedStyle != null) {
			return touchedStyle;
		}
		return if (normalStyle == null) new Style() else normalStyle;
	}
	def addNewProperty(String propName, Object value) {
		newProperties.put(propName,value);
	}
	def hasProperty(String propName) {
		return newProperties.containsKey(propName);
	}
	
	def void watchTree() {
		androidView.viewTreeObserver.addOnGlobalLayoutListener([
			normalStyle._computedX = androidView.x
			normalStyle._computedY = androidView.y
			androidView.viewTreeObserver.removeOnGlobalLayoutListener(self)
		])
	}
	
	def void initAndroidView() {
		createBackgroundDrawable();
		updateTextColorDrawable();
		androidView.onClickListener = this;
		androidView.onTouchListener = this;
		
		if (normalStyle._computedX == null) {
			watchTree();
		}
	}
	
	def void applyAttributes() {
		if (androidView != null) {
			Log.d("Latte", "Style object for "+this+" : "+ _style);
			androidView.enabled = enabled;
			
			if (pendingStyle == null && activeStyle == normalStyle) {
				pendingStyle = normalStyle;
				Log.d("Latte", this+": Applying active style "+normalStyle)
				// Shouldn't clone, apply should have the same effect of clone
				_style.cloneFrom(normalStyle);
				activeStyle.applyStyle(this);
			} else if (pendingStyle != activeStyle && pendingStyle != null) {
				pendingStyle = activeStyle;
				var oldAnim = currentAnimation; 
				currentAnimation = pendingStyle.createAnimatorFrom(_style, this, activeStyle == normalStyle)
				if (oldAnim != null) {
					oldAnim.cancel();
				}
				currentAnimation.start;
			}
		}
	}
	
	override onClick(View v) {
		if (onTap != null) {
			onTap.apply(LatteView.this);
		}				
	}
	
	override onTouch(View v, MotionEvent e) {	
		var handled = false;		
		if (onTouch != null && e.action == MotionEvent.ACTION_DOWN) {
			handled = onTouch.apply(this,e);
		}
		if (enabled) { 
			if (e.action == MotionEvent.ACTION_DOWN) {
				touched = true;				
			} else if (e.action == MotionEvent.ACTION_UP) {
				touched = false;
			}
		}
		if (onTouch != null && e.action == MotionEvent.ACTION_UP) {
			handled = onTouch.apply(this,e);
		}				
		return handled;
	}
	
	
	def Point getMeasuredSize() {
		return getMeasuredSize(activeStyle);
	}
	
	def getWindowWidth() {
		androidView.context.getResources().getDisplayMetrics().widthPixels
	}
	
	def getWindowHeight() {
		androidView.context.getResources().getDisplayMetrics().heightPixels
	}
	
	def Point getMeasuredSize(Style forStyle) {
	    var widthMeasureSpec = if (forStyle.width == LayoutParams.MATCH_PARENT) {
	    	var parentWidth = if (nonVirtualParent != null) {
	    		nonVirtualParent.measuredSize.x;
	    	} else windowWidth;
	    	MeasureSpec.makeMeasureSpec(parentWidth, MeasureSpec.EXACTLY);
	    } else if (forStyle.width == LayoutParams.WRAP_CONTENT) {
	    	MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED);
	    } else {
	    	MeasureSpec.makeMeasureSpec(forStyle.width, MeasureSpec.EXACTLY);
	    }
	    
		var heightMeasureSpec = if (forStyle.height == LayoutParams.MATCH_PARENT) {
	    	var parentHeight = if (nonVirtualParent != null) {
	    		nonVirtualParent.measuredSize.y;
	    	} else windowHeight;
	    	MeasureSpec.makeMeasureSpec(parentHeight, MeasureSpec.EXACTLY);
	    } else if (forStyle.height == LayoutParams.WRAP_CONTENT) {
	    	MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED);
	    } else {
	    	MeasureSpec.makeMeasureSpec(forStyle.height, MeasureSpec.EXACTLY);
	    }
		androidView.measure(widthMeasureSpec, heightMeasureSpec);
		return new Point(androidView.measuredWidth,androidView.measuredHeight);
	}

	def createBackgroundDrawable() {
		if (backgroundDrawable == null) {
			backgroundDrawable = new GradientDrawable();
			shapeDrawable = new ShapeDrawable();
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
				androidView.background = new RippleDrawable(new ColorStateList(#[], #[]),this.backgroundDrawable, this.shapeDrawable);
			} else {			
				androidView.background =  new codetail.graphics.drawables.RippleDrawable(new ColorStateList(#[],#[]),this.backgroundDrawable, this.shapeDrawable);
			}
		}
	}
	def updateTextColorDrawable() {
		
		var List<List<Integer>> colorStates = newArrayList
		var List<Integer> colorList = newArrayList
		if (touchedStyle != null) {
			colorStates += #[ R.attr.state_enabled, R.attr.state_pressed]
			colorList += Style::asColor(touchedStyle.textColor)
		}
		colorStates += #[R.attr.state_enabled, -R.attr.state_pressed ]
		colorList += Style::asColor(style.textColor)
		
		if (disabledStyle != null) {
			colorStates += #[ -R.attr.state_enabled ]
			colorList += Style::asColor(disabledStyle.textColor)
		}
		if (androidView instanceof TextView) {
			val int[][] colorStatesArray = intArray(colorStates.size);
			var i = 0;
			for (state : colorStates) {
				colorStatesArray.set(i,state as int[])
				i++
			}
			androidView.textColor = new ColorStateList(colorStatesArray, colorList);	
		}
	}
	
	def View createAndroidView(Activity a) { null; }
	def void onChildrenAdded() {}
		
//	def addChild(int index, LatteView parent) {
//		parent._children.add(this.children.get(index));
//		this.children.get(index).parentView = parent;
//	}
//	
	def addChild(int index, LatteView newChild) {
		// TODO: 
		// Compare child with existing subview
		// If accepted then just call render in existing subview after transferring properties
		// If not, then add new subview
		if (index < subviews.size) {
			if (sameView(subviews.get(index),newChild)) {
				subviews.get(index).copyStateProps(newChild)
				subviews.get(index).render();
			} else {
				subviews.set(index,newChild)
				newChild.render();
			}
		} else {
			subviews.add(index,newChild);
			newChild.render();
		}
	}
	
	
	
	
	def <T extends LatteView> void processNode(LatteView parent, String id, (T)=>void attrs, (T)=>void children) {
		isRendering = true;
		parentView = parent as LatteView;
		if (parent != null) {
			parent.children.add(this);
		}

		if (attrs != null) {
			attributesProc = attrs as (LatteView)=>void;
			attrs.apply(this as T);
		}
		if (children != null) {
			layoutProc = children as (LatteView)=>void;
			children.apply(this as T);
		}
		isRendering = false;
	}


	def setAttribute(String key, Object value) {
		attributes.put(key, value);
		onStateChanged(key);
	}

	def onStateChanged(String... states) {
		if (!isRendering) {
			Log.d("Latte", this+" : State changed "+ states.join(","))
			handleStateChanged
		}
	}
	
	def void handleStateChanged() {
		this.render();
		buildAndroidViewTree(activity,rootAndroidView.layoutParams);	
	}
		
	def sameView(LatteView leftView, LatteView rightView) {
		if (leftView.class == rightView.class) {
			return true;
		}
		return false;
	}
	
	def void compareView(LatteView newView, LatteView oldView) {
		// Compare children 
		// TODO: Should only copy properties
		 

		oldView.normalStyle.cloneFrom(newView.normalStyle);
		oldView.touchedStyle.cloneFrom(newView.touchedStyle);
		oldView.disabledStyle.cloneFrom(newView.disabledStyle);
		if (oldView.copyStateProps(newView)) {
			Log.d("Latte", this +" copied properties "+newView.newProperties.keySet.join(","));
//			oldView.onStateChanged(newView.newProperties.keySet.join(","));			
		} else {
			Log.d("Latte", this +" Nothing was copied");
		}
		for (var i =0; i < newView.subviews.size; i++) {
			if (oldView.subviews.size <= i) {
				newView.subviews.get(i).parentView = oldView;
				Log.d("Latte", "Added new view "+ newView.subviews.get(i));
				oldView.subviews.add(newView.subviews.get(i))
			} else {
				var oldChildView = oldView.subviews.get(i);
				var newChildView = newView.subviews.get(i);
				Log.d("Latte", this +": Comparing child "+ newChildView +" with "+oldChildView);
				if (this.sameView(oldChildView,newChildView)) {
					// Accepted ?
					if (oldChildView instanceof Button && newChildView instanceof Button) {
						Log.d("Latte", oldChildView +" ((VS)) "+ newChildView); 							
						
						Log.d("Latte", (oldChildView as Button).label +" ((VS)) "+ (newChildView as Button).label); 							
//						Log.d("Latte", (oldChildView.androidView as android.widget.Button).text +" VS "+ (newChildView.androidView as android.widget.Button).text); 	
					}
					compareView(newChildView, oldChildView);
					// Accepted ?
					if (oldChildView instanceof Button && newChildView instanceof Button) {
						Log.d("Latte", "AFTER :" +oldChildView +" ((VS)) "+ newChildView); 													
						Log.d("Latte",  "AFTER :" +(oldChildView as Button).label +" ((VS)) "+ (newChildView as Button).label); 							
 	
					}					
				} else {
					// Not accepted, replace with the new child
					newChildView.parentView = oldView;
					// RODO: Maybe recycle old view ?
					oldView.subviews.set(i, newChildView);								
				}
			}					
		}

	}
	
	
	def LayoutParams createLayoutParams(int width, int height) {
		return null;
	}
	
	def void render() {
		this.children = newArrayList();
		if (layoutProc != null) {
			layoutProc.apply(this);
		}		
	 	// This view doesn't have a render. All children are considered subviews
	 	Log.d("Latte", "in "+this+" children are "+ this.children.size)
		for (var i =0 ; i < this.children.size; i++) {
			var newChild = this.children.get(i);
			this.addChild(i,newChild);
		}	
	}
	
	def LatteView getNonVirtualParent() {
		if (parentView == null) {
			return null;
		}
		if (parentView.androidView != null) {
			return parentView;
		}
		return parentView.nonVirtualParent
	}
	
	def View getRootAndroidView() {
		if (this.androidView == null) {
			return this.subviews.get(0).rootAndroidView
		}
		return this.androidView
	}
	
	def View buildAndroidViewTree(Activity a, ViewGroup.LayoutParams lp) {
		// First build my view
		this.activity = a;
		var myView = if (this.androidView == null) {
			this.androidView = createAndroidView(a); 
			if (this.androidView != null) {
				initAndroidView();
			}
			this.androidView
		} else this.androidView;
		if (myView == null) {
			// If we don't have native android view, then we are virtual node
			return this.subviews.get(0).buildAndroidViewTree(a, lp);
		}
		this.androidView = myView;
		if (this.androidView.id == -1 && this.id != null) {
			this.androidView.id = this.id.hashCode
		}
		if (this.androidView.layoutParams == null) {
			this.androidView.layoutParams = lp;
		}

		if (subviews.size > 0) {
			var myContainer = myView as ViewGroup
			var i = 0;
			for (LatteView v : subviews) {
				var childLP = createLayoutParams(v.normalStyle.width, v.normalStyle.height);
				var View childView = v.buildAndroidViewTree(a, childLP);
				if (i >= myContainer.childCount) {
					myContainer.addView(childView, i, childLP)	
				} else if (myContainer.getChildAt(i) == childView) {
				} else {
					childView.layoutParams = childLP;
					myContainer.addView(childView,i, childLP);
				}
				i++;
			}
			for (var z = i; z < myContainer.childCount; z++) {
				myContainer.removeViewAt(z);
			}
			this.applyAttributes();
			onChildrenAdded();
		} else {
			this.applyAttributes();
		}
		
		return myView;
	}
	
	def void renderOn(Activity a) {
		activity = a;
		this.processNode(null,null,null, null);
		this.render();
		this.buildAndroidViewTree(a, new FrameLayout.LayoutParams(this.normalStyle.width, this.normalStyle.height))
		a.setContentView(this.rootAndroidView);		
	}
	
}